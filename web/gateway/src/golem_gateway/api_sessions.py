"""API router: session list / detail / delete endpoints.

GET    /v1/projects/{project_id}/sessions?limit=100
GET    /v1/projects/{project_id}/sessions/{session_id}
DELETE /v1/projects/{project_id}/sessions/{session_id}
"""

from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Query, Request

from golem_gateway.claude_sessions import delete_claude_session, gc_orphaned_claude_sessions
from golem_gateway.registry import ProjectRegistry
from golem_gateway.sessions_db import SessionDetail, SessionSummary, get_session_store

router = APIRouter(prefix="/v1/projects/{project_id}/sessions", tags=["sessions"])


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


@router.get("", response_model=list[SessionSummary])
async def list_sessions(
    project_id: str,
    limit: int = Query(default=100, ge=1, le=1000),
    registry: ProjectRegistry = Depends(get_registry),
) -> list[SessionSummary]:
    """Return sessions for the project sorted by updated_at DESC."""
    project_path = await _resolve_project_path(project_id, registry)
    store = get_session_store(project_path)
    return store.list_sessions(limit=limit)


@router.get("/{session_id}", response_model=SessionDetail)
async def get_session(
    project_id: str,
    session_id: str,
    registry: ProjectRegistry = Depends(get_registry),
) -> SessionDetail:
    """Return full session detail including all messages, or 404."""
    project_path = await _resolve_project_path(project_id, registry)
    store = get_session_store(project_path)
    detail = store.get_session(session_id)
    if detail is None:
        raise HTTPException(
            status_code=404, detail=f"session {session_id!r} not found"
        )
    return detail


@router.delete("/{session_id}", status_code=204)
async def delete_session(
    project_id: str,
    session_id: str,
    registry: ProjectRegistry = Depends(get_registry),
) -> None:
    """Delete a session and all its messages.  Returns 204 on success, 404 if not found."""
    project_path = await _resolve_project_path(project_id, registry)
    store = get_session_store(project_path)
    deleted = store.delete_session(session_id)
    if not deleted:
        raise HTTPException(
            status_code=404, detail=f"session {session_id!r} not found"
        )
    # Best-effort: remove claude's per-session file so disk doesn't grow unbounded.
    delete_claude_session(project_path, session_id)


@router.post("/cleanup", status_code=200)
async def cleanup_orphaned_sessions(
    project_id: str,
    registry: ProjectRegistry = Depends(get_registry),
) -> dict[str, int]:
    """Delete claude session files whose UUIDs are not in our SQLite store.

    Safe to call at any time — only UUID-named .jsonl files are removed.
    Returns {"deleted": N}.

    Note: this endpoint has no auth or rate limit. The Gateway is bound to
    127.0.0.1 and the UI surfaces this only via a confirm dialog in
    ProfileCard, so accidental triggers from a browser tab are mitigated.
    If multi-user / non-localhost deployment ever happens, gate this with
    auth + per-project quota.
    """
    project_path = await _resolve_project_path(project_id, registry)
    store = get_session_store(project_path)
    # Use list_all_session_ids (no pagination cap) so GC never wrongly nukes
    # real sessions when a project exceeds an arbitrary list_sessions limit.
    known_ids = store.list_all_session_ids()
    deleted = gc_orphaned_claude_sessions(project_path, known_ids)
    return {"deleted": deleted}
