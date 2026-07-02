"""APIRouter for missions.

GET  /v1/projects/{project_id}/missions?limit=20
GET  /v1/projects/{project_id}/missions/{mission_id}
POST /v1/projects/{project_id}/missions/{mission_id}/run
"""

from __future__ import annotations

import json
import logging
import re
from pathlib import Path
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel, Field

from golem_gateway.forge_runner import ForgeRunner
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


class MissionRunRequest(BaseModel):
    soul: str = Field(default="", max_length=64)
    verifier: str = Field(default="", max_length=64)


class MissionRunResponse(BaseModel):
    run_id: str


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


@router.get("/missions/{mission_id}", response_model=MissionSummary)
async def get_mission(
    project_id: str,
    mission_id: str,
    registry: ProjectRegistry = Depends(_get_registry),
) -> MissionSummary:
    """Fetch a single mission by id (msn_* directory name)."""
    if not _MSN_DIR_RE.match(mission_id):
        raise HTTPException(status_code=400, detail="invalid mission id")

    project_path = await _resolve_project_path(project_id, registry)
    state_path = project_path / ".golem" / "missions" / mission_id / "state.json"
    if not state_path.is_file():
        raise HTTPException(status_code=404, detail=f"mission {mission_id!r} not found")

    data = _load_mission(state_path)
    if data is None:
        raise HTTPException(status_code=500, detail="mission state.json is corrupt")
    return MissionSummary(**data)


@router.post("/missions/{mission_id}/run", response_model=MissionRunResponse)
async def run_mission(
    project_id: str,
    mission_id: str,
    body: MissionRunRequest,
    request: Request,
    registry: ProjectRegistry = Depends(_get_registry),
) -> MissionRunResponse:
    """Start the deterministic mission loop (`forge mission run`) as a forge run.

    Returns the forge run_id — the client streams progress via the existing
    GET /v1/forge-runs/{run_id}/events SSE and stops via DELETE on the same id.
    The long-form MAX_FLOW_SECONDS ceiling applies (forge_runner argv detection).
    """
    if not _MSN_DIR_RE.match(mission_id):
        raise HTTPException(status_code=400, detail="invalid mission id")

    project_path = await _resolve_project_path(project_id, registry)
    state_path = project_path / ".golem" / "missions" / mission_id / "state.json"
    if not state_path.is_file():
        raise HTTPException(status_code=404, detail=f"mission {mission_id!r} not found")

    runner: ForgeRunner = request.app.state.forge_runner

    args = ["run", mission_id]
    if body.soul:
        args.append(body.soul)
        if body.verifier:
            args.append(body.verifier)

    try:
        run = await runner.spawn(
            command="mission",
            args=args,
            project_id=project_id,
            project_path=project_path,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except RuntimeError as exc:
        logger.error("failed to spawn mission run: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    return MissionRunResponse(run_id=run.run_id)
