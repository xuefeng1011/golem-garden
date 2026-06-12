"""APIRouter for mission listing.

GET /v1/projects/{project_id}/missions?limit=20
"""

from __future__ import annotations

import json
import logging
import re
from pathlib import Path
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel

from golem_gateway.registry import ProjectRegistry

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1/projects/{project_id}", tags=["missions"])

# Safe mission directory name: msn_ prefix + word chars only.
_MSN_DIR_RE = re.compile(r"^msn_[A-Za-z0-9_]+$")


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------


class MissionTask(BaseModel):
    idx: int
    task: str
    soul: str
    status: str


class MissionSummary(BaseModel):
    id: str
    goal: str
    status: str
    created: str
    tasks: list[MissionTask]


# ---------------------------------------------------------------------------
# Dependency
# ---------------------------------------------------------------------------


def _get_registry(request: Request) -> ProjectRegistry:
    return request.app.state.registry  # type: ignore[no-any-return]


async def _resolve_project_path(
    project_id: str, registry: ProjectRegistry
) -> Path:
    """Return project_path or raise 404."""
    project = await registry.get(project_id)
    if project is None:
        raise HTTPException(status_code=404, detail=f"project {project_id!r} not found")
    return Path(project.path)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _load_mission(state_path: Path) -> dict[str, Any] | None:
    """Parse a state.json and return a MissionSummary-compatible dict, or None on error."""
    try:
        raw = json.loads(state_path.read_text(encoding="utf-8"))
    except Exception:
        logger.warning("missions: skipping corrupt state.json: %s", state_path)
        return None

    try:
        tasks = [
            {
                "idx": t["idx"],
                "task": t["task"],
                "soul": t.get("soul", ""),
                "status": t["status"],
            }
            for t in raw.get("tasks", [])
        ]
        return {
            "id": raw["id"],
            "goal": raw["goal"],
            "status": raw["status"],
            "created": raw["created"],
            "tasks": tasks,
        }
    except (KeyError, TypeError):
        logger.warning("missions: missing required field in %s", state_path)
        return None


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------


@router.get("/missions", response_model=list[MissionSummary])
async def list_missions(
    project_id: str,
    limit: int = Query(default=20, ge=1, le=100),
    registry: ProjectRegistry = Depends(_get_registry),
) -> list[MissionSummary]:
    """List missions sorted by directory mtime descending (newest first)."""
    project_path = await _resolve_project_path(project_id, registry)
    missions_dir = project_path / ".golem" / "missions"

    if not missions_dir.is_dir():
        return []

    # Collect (mtime, state_path) for valid msn_* directories.
    entries: list[tuple[float, Path]] = []
    for entry in missions_dir.iterdir():
        if not entry.is_dir():
            continue
        if not _MSN_DIR_RE.match(entry.name):
            continue
        state_path = entry / "state.json"
        if not state_path.is_file():
            continue
        entries.append((entry.stat().st_mtime, state_path))

    # Sort newest first.
    entries.sort(key=lambda x: x[0], reverse=True)

    results: list[MissionSummary] = []
    for _, state_path in entries:
        if len(results) >= limit:
            break
        data = _load_mission(state_path)
        if data is None:
            continue
        try:
            results.append(MissionSummary(**data))
        except Exception:
            logger.warning("missions: model validation failed for %s", state_path)

    return results
