"""APIRouter for /v1/projects endpoints."""

from __future__ import annotations

import logging
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from golem_gateway.registry import Project, ProjectRegistry
from golem_gateway.session_manager import SessionManager
from golem_gateway.sessions_db import evict_session_store

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1/projects", tags=["projects"])


# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

def get_registry(request: Request) -> ProjectRegistry:
    return request.app.state.registry  # type: ignore[no-any-return]


def get_manager(request: Request) -> SessionManager:
    return request.app.state.session_manager  # type: ignore[no-any-return]


# ---------------------------------------------------------------------------
# Request model
# ---------------------------------------------------------------------------

class CreateProjectRequest(BaseModel):
    name: str
    path: str


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@router.get("", response_model=list[Project])
async def list_projects(
    registry: ProjectRegistry = Depends(get_registry),
) -> list[Project]:
    """Return all registered projects."""
    return await registry.list()


@router.post("", response_model=Project, status_code=201)
async def create_project(
    body: CreateProjectRequest,
    registry: ProjectRegistry = Depends(get_registry),
) -> Project:
    """Register a new project. 400 on invalid input. 409 on duplicate path."""
    try:
        return await registry.create(name=body.name, path=body.path)
    except ValueError as exc:
        msg = str(exc)
        # Duplicate path returns 409; other validation errors return 400.
        if "already registered" in msg:
            raise HTTPException(status_code=409, detail=msg) from exc
        raise HTTPException(status_code=400, detail=msg) from exc


@router.delete("/{project_id}", status_code=204)
async def delete_project(
    project_id: str,
    registry: ProjectRegistry = Depends(get_registry),
    manager: SessionManager = Depends(get_manager),
) -> None:
    """Delete a project and terminate any active runs for it.

    F4 (TOCTOU): we must remove the project from the registry FIRST. Once it is
    gone, any concurrent spawn attempt will fail to resolve the project and
    404 instead of leaking a new Run between our terminate-then-delete steps.
    Only after the registry mutation do we sweep runs that were already
    in-flight at the moment of deletion.

    Zen M3: also evict the cached SessionStore so a stale connection does not
    pin the .golem/sessions.db file (Windows) and so re-registering a project
    at the same path gets a fresh store.
    """
    # Look up the project BEFORE delete so we can evict the cached store using
    # its on-disk path. registry.delete returns only a bool today.
    project_before = await registry.get(project_id)

    found = await registry.delete(project_id)
    if not found:
        raise HTTPException(status_code=404, detail=f"project {project_id!r} not found")

    # Sweep any runs that were already in-flight before the registry delete.
    terminated = await manager.terminate_runs_for_project(project_id)
    if terminated:
        logger.info(
            "terminated %d active run(s) for project %s", terminated, project_id
        )

    # Evict the SessionStore cache entry now that no run can reference it.
    if project_before is not None:
        try:
            evict_session_store(Path(project_before.path))
        except Exception:
            logger.exception(
                "failed to evict session store cache for project %s", project_id
            )
