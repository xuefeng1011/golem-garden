"""APIRouter for run trajectory listing and trace pagination.

GET /v1/projects/{project_id}/runs?limit=50&offset=0
GET /v1/projects/{project_id}/runs/{run_id}/trace?offset=0&limit=200
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel

from golem_gateway.registry import ProjectRegistry
from golem_gateway.runs_store import load_all_metas, load_trace_lines

router = APIRouter(prefix="/v1/projects/{project_id}", tags=["traces"])

# UUID v4 pattern — mirrors claude_sessions._UUID_RE (path traversal guard G4).
_UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
    re.IGNORECASE,
)


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------

class RunMeta(BaseModel):
    run_id: str
    session_id: str
    soul: str
    model: str
    source: str
    ts_start: str
    duration_ms: int
    tokens_in: int
    tokens_out: int
    tokens_cache: int
    # cache hit-rate split — absent in pre-2026-06-13 metas (None = unknown)
    tokens_cache_read: int | None = None
    tokens_cache_creation: int | None = None
    cost_usd: float
    result: str
    tool_counts: dict[str, int]


class TraceResponse(BaseModel):
    run_id: str
    total_lines: int
    offset: int
    lines: list[dict[str, Any]]


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
# Routes
# ---------------------------------------------------------------------------

@router.get("/runs", response_model=list[RunMeta])
async def list_runs(
    project_id: str,
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    registry: ProjectRegistry = Depends(_get_registry),
) -> list[RunMeta]:
    """List completed run metas sorted by mtime descending."""
    project_path = await _resolve_project_path(project_id, registry)
    runs_dir = project_path / ".golem" / "runs"
    all_metas = load_all_metas(runs_dir)

    results: list[RunMeta] = []
    for data in all_metas[offset : offset + limit]:
        try:
            results.append(RunMeta(**data))
        except Exception:
            continue

    return results


@router.get("/runs/{run_id}/trace", response_model=TraceResponse)
async def get_run_trace(
    project_id: str,
    run_id: str,
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=200, ge=1, le=1000),
    registry: ProjectRegistry = Depends(_get_registry),
) -> TraceResponse:
    """Return a paginated slice of raw JSONL lines for a run trace."""
    # G4: UUID-only validation to block path traversal.
    if not _UUID_RE.match(run_id):
        raise HTTPException(status_code=400, detail="run_id must be a valid UUID")

    project_path = await _resolve_project_path(project_id, registry)
    jsonl_path = project_path / ".golem" / "runs" / f"{run_id}.jsonl"

    if not jsonl_path.is_file():
        raise HTTPException(status_code=404, detail=f"run {run_id!r} not found")

    all_lines = load_trace_lines(jsonl_path)
    page = all_lines[offset : offset + limit]

    return TraceResponse(
        run_id=run_id,
        total_lines=len(all_lines),
        offset=offset,
        lines=page,
    )
