"""APIRouter for /v1/studios endpoints (Flow Studio — STUDIO_PLAN.md §4).

A studio is a self-contained GOLEM_PROJECT folder registered with
kind="studio" so it never appears in the existing /v1/projects screen.
Creation registers the path, then synchronously runs
`forge studio init <path> <name> <goal>` to scaffold the studio folder
(.golem/souls, .golem/flows, flowsmith copy). Init failure rolls back the
registry entry.
"""

from __future__ import annotations

import asyncio
import logging
import shutil
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from golem_gateway.config import (
    BASH_BIN,
    FORGE_SH_BASH_PATH,
    FORGE_SH_PATH,
    build_forge_subprocess_env,
    to_bash_path,
)
from golem_gateway.registry import Project, ProjectRegistry

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1/studios", tags=["studios"])


# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

def get_registry(request: Request) -> ProjectRegistry:
    return request.app.state.registry  # type: ignore[no-any-return]


# ---------------------------------------------------------------------------
# Request model
# ---------------------------------------------------------------------------

class CreateStudioRequest(BaseModel):
    name: str
    path: str
    goal: str = ""


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

async def _run_studio_init(project_path: Path, name: str, goal: str) -> str | None:
    """Run `bash forge.sh studio init <path> <name> <goal>` synchronously.

    Modeled on api_flows._validate_with_forge, but init failure is fatal here
    (a studio with no scaffold is unusable) — so unlike that advisory helper,
    a missing forge.sh IS reported as an error rather than swallowed.

    Returns None on success (rc=0), or an error string on failure (nonzero
    rc, timeout, or missing bash/forge.sh).
    """
    if not FORGE_SH_PATH.is_file():
        return f"forge.sh not found at {FORGE_SH_PATH}"

    env = build_forge_subprocess_env(project_path)

    try:
        proc = await asyncio.create_subprocess_exec(
            BASH_BIN,
            FORGE_SH_BASH_PATH,
            "studio",
            "init",
            to_bash_path(project_path),
            name,
            goal,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            stdin=asyncio.subprocess.DEVNULL,
            cwd=str(project_path),
            env=env,
        )
        try:
            _stdout_b, stderr_b = await asyncio.wait_for(proc.communicate(), timeout=30.0)
        except asyncio.TimeoutError:
            proc.kill()
            await proc.wait()
            return "forge studio init timed out"

        if proc.returncode != 0:
            stderr_text = stderr_b.decode("utf-8", errors="replace").strip()
            return stderr_text or f"forge studio init exited rc={proc.returncode}"
        return None
    except (OSError, FileNotFoundError) as exc:
        return f"forge studio init subprocess failed: {exc}"


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@router.post("", response_model=Project, status_code=201)
async def create_studio(
    body: CreateStudioRequest,
    registry: ProjectRegistry = Depends(get_registry),
) -> Project:
    """Register a new studio and scaffold it via `forge studio init`.

    400 on invalid input (bad path/name, or name/goal with newlines).
    409 on duplicate path. 500 if `forge studio init` fails — the registry
    entry is rolled back in that case so the studio does not linger half-set-up.
    """
    # Defense-in-depth: name/goal/path flow into list-form subprocess argv (no
    # shell interpolation), but newlines are rejected up front to keep
    # forge.sh's own line-oriented parsing (studio.json / soul frontmatter)
    # sane. Checked before registry.create so no entry is ever half-written.
    if "\n" in body.name or "\r" in body.name:
        raise HTTPException(status_code=400, detail="name must not contain newlines")
    if "\n" in body.goal or "\r" in body.goal:
        raise HTTPException(status_code=400, detail="goal must not contain newlines")
    if "\n" in body.path or "\r" in body.path:
        raise HTTPException(status_code=400, detail="path must not contain newlines")

    # Rollback bookkeeping: only remove the studio dir on init failure if WE
    # created it — a pre-existing directory (registered against an existing
    # folder) must survive rollback untouched.
    try:
        pre_existed = Path(body.path).expanduser().resolve().is_dir()
    except OSError:
        pre_existed = False

    try:
        # create_missing: 스튜디오는 "새 폴더 지정" UX — 허용 루트 안이면 자동 생성
        project = await registry.create(
            name=body.name, path=body.path, kind="studio", create_missing=True
        )
    except ValueError as exc:
        msg = str(exc)
        if "already registered" in msg:
            raise HTTPException(status_code=409, detail=msg) from exc
        raise HTTPException(status_code=400, detail=msg) from exc

    err = await _run_studio_init(Path(project.path), project.name, body.goal)
    if err:
        deleted = await registry.delete(project.id)
        if not deleted:
            logger.warning(
                "studio init rollback: registry entry %s (%s) was already gone",
                project.id,
                project.path,
            )
        if not pre_existed:
            shutil.rmtree(project.path, ignore_errors=True)
        logger.error("studio init failed for %s (%s): %s", project.id, project.path, err)
        raise HTTPException(status_code=500, detail=f"studio init failed: {err}")

    return project


@router.get("", response_model=list[Project])
async def list_studios(
    registry: ProjectRegistry = Depends(get_registry),
) -> list[Project]:
    """Return all registered studios (kind=studio only)."""
    return await registry.list(kind="studio")


@router.delete("/{studio_id}", status_code=204)
async def delete_studio(
    studio_id: str,
    registry: ProjectRegistry = Depends(get_registry),
) -> None:
    """Unregister a studio. 404 if unknown or not a studio.

    Only removes the registry entry — the folder is left on disk (unlike the
    auto-rollback path in create_studio, a user-initiated delete should not
    silently destroy a scaffolded studio's files).
    """
    project = await registry.get(studio_id)
    if project is None or project.kind != "studio":
        raise HTTPException(status_code=404, detail=f"studio {studio_id!r} not found")
    await registry.delete(studio_id)
