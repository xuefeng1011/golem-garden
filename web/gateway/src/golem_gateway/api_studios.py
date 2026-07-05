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
import json
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
    redact_stderr,
    to_bash_path,
)
from golem_gateway.registry import Project, ProjectRegistry

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1/studios", tags=["studios"])

# Separate router for /v1/studio-presets: an engine-global resource (no
# project scoping), so it cannot share the /v1/studios-prefixed router above.
preset_router = APIRouter(tags=["studios"])


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


class StudioOut(Project):
    """Project + goal — an enriched response-only view (BACKLOG.md P0-3).

    goal is NOT persisted on the registry's Project model (GET /v1/projects
    stays untouched); it is read best-effort from the studio's own
    studio.json on list, and echoed back from the request body on create.
    """

    goal: str = ""


class PresetSummary(BaseModel):
    """Lean preset listing — id/name/description only (no agents/steps)."""

    id: str
    name: str
    description: str


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _read_studio_goal(path: str) -> str:
    """Best-effort read of a studio's goal from its studio.json.

    Missing file, unreadable, corrupt JSON, or a non-string/missing "goal"
    field all fall back to "" rather than raising — this is a display nice-
    to-have, not a source of truth.
    """
    try:
        data = json.loads((Path(path) / "studio.json").read_text(encoding="utf-8"))
    except Exception:
        return ""
    if isinstance(data, dict):
        goal = data.get("goal", "")
        if isinstance(goal, str):
            return goal
    return ""


def _studio_presets_dir() -> Path:
    """Engine-global presets directory: <engine_root>/templates/studio-presets.

    Broken out as its own function (rather than inlining FORGE_SH_PATH.parent
    / ... at the call site) so tests can monkeypatch just this to point at a
    tmp dir without disturbing FORGE_SH_PATH itself.
    """
    return FORGE_SH_PATH.parent / "templates" / "studio-presets"


def _scan_studio_presets() -> list[PresetSummary]:
    """Scan the presets dir for *.json files and return id/name/description.

    Missing directory -> []. Each file is parsed independently; a corrupt
    file or one missing a required field is skipped silently (this is a
    display listing, not a validating one) rather than failing the whole
    request. Sorted by id for a stable listing order.
    """
    presets_dir = _studio_presets_dir()
    if not presets_dir.is_dir():
        return []

    # 파일명 정렬은 최종 id 정렬에 밀려 무의미하므로 glob 순서 그대로 순회.
    # 동일 id 를 선언한 파일이 둘이면 먼저 읽힌 쪽만 유지(경고) — id 는
    # 클라이언트 목록 키로 쓰이므로 중복이 UI 버그로 번지지 않게 차단.
    by_id: dict[str, PresetSummary] = {}
    for f in presets_dir.glob("*.json"):
        try:
            data = json.loads(f.read_text(encoding="utf-8"))
            preset = PresetSummary(
                id=data["id"], name=data["name"], description=data["description"]
            )
        except Exception:
            logger.warning("skipping unreadable/invalid studio preset file: %s", f)
            continue
        if preset.id in by_id:
            logger.warning("duplicate studio preset id %r in %s — keeping first", preset.id, f)
            continue
        by_id[preset.id] = preset

    return sorted(by_id.values(), key=lambda p: p.id)


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
            if not stderr_text:
                return f"forge studio init exited rc={proc.returncode}"
            # Full text server-side only (may contain absolute paths); the
            # returned string (wrapped into the 500 detail by the caller) is
            # redacted.
            logger.error(
                "forge studio init failed (rc=%s) for %s: %s",
                proc.returncode,
                project_path,
                stderr_text,
            )
            return redact_stderr(stderr_text)
        return None
    except (OSError, FileNotFoundError) as exc:
        return f"forge studio init subprocess failed: {exc}"


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@router.post("", response_model=StudioOut, status_code=201)
async def create_studio(
    body: CreateStudioRequest,
    registry: ProjectRegistry = Depends(get_registry),
) -> StudioOut:
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

    # goal echoed from the request, not re-read from disk — forge studio init
    # already wrote it into studio.json, but echoing avoids a redundant read
    # and matches what the client just submitted.
    return StudioOut(**project.model_dump(), goal=body.goal)


@router.get("", response_model=list[StudioOut])
async def list_studios(
    registry: ProjectRegistry = Depends(get_registry),
) -> list[StudioOut]:
    """Return all registered studios (kind=studio only), goal read best-effort."""
    projects = await registry.list(kind="studio")
    return [
        StudioOut(**p.model_dump(), goal=_read_studio_goal(p.path)) for p in projects
    ]


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


@preset_router.get("/v1/studio-presets", response_model=list[PresetSummary])
def list_studio_presets() -> list[PresetSummary]:
    """Return engine-global studio presets (no project scoping).

    Scans <engine_root>/templates/studio-presets/*.json — corrupt or
    field-missing files are skipped; a missing directory returns [].
    """
    return _scan_studio_presets()
