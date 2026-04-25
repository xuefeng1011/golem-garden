"""APIRouter for activity, overview, and board endpoints."""

from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Request

from fastapi import Query

from golem_gateway.activity import (
    AchievementEntry,
    BoardResponse,
    BudgetResponse,
    ChemistryResponse,
    MailboxEntry,
    OverviewResponse,
    SessionSummary,
    SkillTreeResponse,
    SoulActivityResponse,
    TimelineEvent,
    build_achievements,
    build_board,
    build_budget,
    build_chemistry,
    build_overview,
    build_skill_tree,
    build_soul_activity,
    build_timeline,
    scan_mailbox,
    scan_sessions,
)
from golem_gateway.registry import ProjectRegistry
from golem_gateway.souls import get_soul_by_id, scan_souls

router = APIRouter(prefix="/v1/projects/{project_id}", tags=["activity"])


# ---------------------------------------------------------------------------
# Dependency
# ---------------------------------------------------------------------------

def get_registry(request: Request) -> ProjectRegistry:
    return request.app.state.registry  # type: ignore[no-any-return]


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

async def _resolve_project(
    project_id: str, registry: ProjectRegistry
) -> tuple[str, Path]:
    """Return (project_name, project_path) or raise 404."""
    project = await registry.get(project_id)
    if project is None:
        raise HTTPException(status_code=404, detail=f"project {project_id!r} not found")
    return project.name, Path(project.path)


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@router.get("/overview", response_model=OverviewResponse)
async def get_project_overview(
    project_id: str,
    registry: ProjectRegistry = Depends(get_registry),
) -> OverviewResponse:
    """Aggregate snapshot: soul counts, recent activity, success rate, cost."""
    name, project_path = await _resolve_project(project_id, registry)
    return build_overview(project_id, name, project_path)


@router.get("/souls/{soul_id}/activity", response_model=SoulActivityResponse)
async def get_soul_activity(
    project_id: str,
    soul_id: str,
    registry: ProjectRegistry = Depends(get_registry),
) -> SoulActivityResponse:
    """Per-SOUL growth-log detail with rank progress."""
    _, project_path = await _resolve_project(project_id, registry)

    soul = get_soul_by_id(project_path, soul_id)
    if soul is None:
        raise HTTPException(status_code=404, detail=f"SOUL '{soul_id}' not found")

    return build_soul_activity(soul_id, soul.rank, project_path)


@router.get("/board", response_model=BoardResponse)
async def get_project_board(
    project_id: str,
    registry: ProjectRegistry = Depends(get_registry),
) -> BoardResponse:
    """Parse .golem/forge-board.md — team table, tech debt, history."""
    _, project_path = await _resolve_project(project_id, registry)
    return build_board(project_path)


@router.get("/forge-sessions", response_model=list[SessionSummary])
async def get_project_forge_sessions(
    project_id: str,
    registry: ProjectRegistry = Depends(get_registry),
) -> list[SessionSummary]:
    """List forge.sh-managed sessions from .golem/sessions/ (legacy file-based).
    Renamed from /sessions to free that path for the SQLite-backed chat history endpoint.
    """
    _, project_path = await _resolve_project(project_id, registry)
    return scan_sessions(project_path)


@router.get("/mailbox", response_model=list[MailboxEntry])
async def get_project_mailbox(
    project_id: str,
    limit: int = Query(default=50, ge=1, le=200),
    registry: ProjectRegistry = Depends(get_registry),
) -> list[MailboxEntry]:
    """Read all SOUL inboxes from .golem/mailbox/, merged and sorted by ts desc."""
    _, project_path = await _resolve_project(project_id, registry)
    return scan_mailbox(project_path, limit=limit)


@router.get("/timeline", response_model=list[TimelineEvent])
async def get_project_timeline(
    project_id: str,
    limit: int = Query(default=50, ge=1, le=200),
    registry: ProjectRegistry = Depends(get_registry),
) -> list[TimelineEvent]:
    """Unified activity feed: growth-log + sessions + mailbox, sorted by ts desc."""
    _, project_path = await _resolve_project(project_id, registry)
    return build_timeline(project_path, limit=limit)


@router.get("/achievements", response_model=list[AchievementEntry])
async def get_project_achievements(
    project_id: str,
    registry: ProjectRegistry = Depends(get_registry),
) -> list[AchievementEntry]:
    """Earned badges from .golem/achievements.jsonl, sorted by earned_at desc."""
    _, project_path = await _resolve_project(project_id, registry)
    return build_achievements(project_path)


@router.get("/chemistry", response_model=ChemistryResponse)
async def get_project_chemistry(
    project_id: str,
    registry: ProjectRegistry = Depends(get_registry),
) -> ChemistryResponse:
    """Team pair chemistry scores from .golem/chemistry.jsonl."""
    _, project_path = await _resolve_project(project_id, registry)
    return build_chemistry(project_path)


@router.get("/budget", response_model=BudgetResponse)
async def get_project_budget(
    project_id: str,
    registry: ProjectRegistry = Depends(get_registry),
) -> BudgetResponse:
    """Cost aggregation from growth-log entries + budget-state.json."""
    _, project_path = await _resolve_project(project_id, registry)
    return build_budget(project_path)


@router.get("/souls/{soul_id}/skill-tree", response_model=SkillTreeResponse)
async def get_soul_skill_tree(
    project_id: str,
    soul_id: str,
    registry: ProjectRegistry = Depends(get_registry),
) -> SkillTreeResponse:
    """Per-SOUL specialization branches derived from frontmatter + growth-log."""
    _, project_path = await _resolve_project(project_id, registry)
    soul = get_soul_by_id(project_path, soul_id)
    if soul is None:
        raise HTTPException(status_code=404, detail=f"SOUL '{soul_id}' not found")
    return build_skill_tree(soul_id, soul.rank, project_path)
