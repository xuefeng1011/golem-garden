"""APIRouter for /v1/projects/{project_id}/souls endpoints."""

from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Request

from golem_gateway.registry import ProjectRegistry
from golem_gateway.souls import SoulDetail, SoulSummary, get_soul_by_id, scan_souls

router = APIRouter(prefix="/v1/projects/{project_id}/souls", tags=["souls"])


# ---------------------------------------------------------------------------
# Dependency
# ---------------------------------------------------------------------------

def get_registry(request: Request) -> ProjectRegistry:
    return request.app.state.registry  # type: ignore[no-any-return]


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

async def _resolve_project_path(
    project_id: str, registry: ProjectRegistry
) -> Path:
    """Look up the project and return its path, or raise 404."""
    project = await registry.get(project_id)
    if project is None:
        raise HTTPException(
            status_code=404, detail=f"project {project_id!r} not found"
        )
    return Path(project.path)


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@router.get("", response_model=list[SoulSummary])
async def list_souls(
    project_id: str,
    registry: ProjectRegistry = Depends(get_registry),
) -> list[SoulSummary]:
    """Return all SOULs for the given project (lean payload — no content field)."""
    project_path = await _resolve_project_path(project_id, registry)
    souls = scan_souls(project_path)
    return [
        SoulSummary(
            id=s.id,
            name=s.name,
            rank=s.rank,
            specialty=s.specialty,
            description=s.description,
            is_coordinator=s.is_coordinator,
        )
        for s in souls
    ]


@router.get("/{soul_id}", response_model=SoulDetail)
async def get_soul(
    project_id: str,
    soul_id: str,
    registry: ProjectRegistry = Depends(get_registry),
) -> SoulDetail:
    """Return a single SOUL including full markdown body."""
    project_path = await _resolve_project_path(project_id, registry)
    soul = get_soul_by_id(project_path, soul_id)
    if soul is None:
        raise HTTPException(status_code=404, detail=f"SOUL '{soul_id}' not found")
    return soul
