"""APIRouter for /v1/projects/{project_id}/skills endpoints."""

from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Request

from golem_gateway.registry import ProjectRegistry
from golem_gateway.skills import SkillDetail, SkillSummary, get_skill_by_id, scan_skills

router = APIRouter(prefix="/v1/projects/{project_id}/skills", tags=["skills"])


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

@router.get("", response_model=list[SkillSummary])
async def list_skills(
    project_id: str,
    registry: ProjectRegistry = Depends(get_registry),
) -> list[SkillSummary]:
    """Return all skills for the given project (lean payload — no content field)."""
    project_path = await _resolve_project_path(project_id, registry)
    details = scan_skills(project_path)
    return [
        SkillSummary(
            id=d.id,
            name=d.name,
            description=d.description,
        )
        for d in details
    ]


@router.get("/{skill_id}", response_model=SkillDetail)
async def get_skill(
    project_id: str,
    skill_id: str,
    registry: ProjectRegistry = Depends(get_registry),
) -> SkillDetail:
    """Return a single skill including full markdown body."""
    project_path = await _resolve_project_path(project_id, registry)
    skill = get_skill_by_id(project_path, skill_id)
    if skill is None:
        raise HTTPException(status_code=404, detail=f"skill '{skill_id}' not found in project")
    return skill
