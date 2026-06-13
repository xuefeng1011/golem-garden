"""APIRouter for flow listing (Flow Engine read view).

GET /v1/projects/{project_id}/flows?limit=20
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

router = APIRouter(prefix="/v1/projects/{project_id}", tags=["flows"])

# Safe flow directory name: uuid or flow_<epoch>_<pid> fallback (lib/flow-dag.sh).
_FLOW_DIR_RE = re.compile(r"^(flow_[A-Za-z0-9_]+|[0-9a-f-]{36})$", re.IGNORECASE)


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------


class FlowStep(BaseModel):
    id: str
    soul: str
    task: str
    deps: list[str]
    status: str
    approval: bool = False
    on_fail: str = "abort"


class FlowSummary(BaseModel):
    flow_id: str
    goal: str
    status: str
    created: str
    steps: list[FlowStep]


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


def _load_flow(state_path: Path) -> dict[str, Any] | None:
    """Parse a flow state.json into a FlowSummary-compatible dict, or None on error."""
    try:
        raw = json.loads(state_path.read_text(encoding="utf-8"))
    except Exception:
        logger.warning("flows: skipping corrupt state.json: %s", state_path)
        return None

    try:
        steps = [
            {
                "id": s["id"],
                "soul": s.get("soul", ""),
                "task": s["task"],
                "deps": s.get("deps", []),
                "status": s.get("status", "pending"),
                "approval": bool(s.get("approval", False)),
                "on_fail": s.get("on_fail", "abort"),
            }
            for s in raw.get("steps", [])
        ]
        return {
            "flow_id": raw["flow_id"],
            "goal": raw["goal"],
            "status": raw["status"],
            "created": raw["created"],
            "steps": steps,
        }
    except (KeyError, TypeError):
        logger.warning("flows: missing required field in %s", state_path)
        return None


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------


@router.get("/flows", response_model=list[FlowSummary])
async def list_flows(
    project_id: str,
    limit: int = Query(default=20, ge=1, le=100),
    registry: ProjectRegistry = Depends(_get_registry),
) -> list[FlowSummary]:
    """List flows sorted by directory mtime descending (newest first)."""
    project_path = await _resolve_project_path(project_id, registry)
    flows_dir = project_path / ".golem" / "flows"

    if not flows_dir.is_dir():
        return []

    entries: list[tuple[float, Path]] = []
    for entry in flows_dir.iterdir():
        if not entry.is_dir():
            continue
        if not _FLOW_DIR_RE.match(entry.name):
            continue
        state_path = entry / "state.json"
        if not state_path.is_file():
            continue
        entries.append((entry.stat().st_mtime, state_path))

    entries.sort(key=lambda x: x[0], reverse=True)

    results: list[FlowSummary] = []
    for _, state_path in entries:
        if len(results) >= limit:
            break
        data = _load_flow(state_path)
        if data is None:
            continue
        try:
            results.append(FlowSummary(**data))
        except Exception:
            logger.warning("flows: model validation failed for %s", state_path)

    return results
