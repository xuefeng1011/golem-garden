"""APIRouter for read-only artifact browsing under a project (BACKLOG.md P0-2).

Flows write output files under an arbitrary project-relative directory
(conventionally ``output/``, see lib/flow.sh's GOLEM_FLOW_OUTPUT_DIR). This
router lets the client list and preview those files without a filesystem
mount — read-only, path-traversal-guarded (mirrors the validation shape used
by api_flows._resolve_project_path + registry's own resolve+relative_to
guard).

GET /v1/projects/{project_id}/artifacts?dir=output
GET /v1/projects/{project_id}/artifacts/content?path=output/report.md
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel

from golem_gateway.registry import ProjectRegistry

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1/projects/{project_id}", tags=["artifacts"])

# Recursion guards — a pathological/huge output tree must not hang the request
# or return an unbounded payload.
_MAX_DEPTH = 4
_MAX_ENTRIES = 500

# Read cap for the content endpoint (256 KiB) and how many leading bytes are
# sniffed for a NUL byte to decide binary vs text.
_CONTENT_CAP_BYTES = 256 * 1024
_BINARY_SNIFF_BYTES = 8 * 1024


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------


class ArtifactEntry(BaseModel):
    path: str
    name: str
    size: int
    mtime: str


class ArtifactContent(BaseModel):
    path: str
    content: str
    truncated: bool
    binary: bool
    size: int


# ---------------------------------------------------------------------------
# Dependency
# ---------------------------------------------------------------------------


def _get_registry(request: Request) -> ProjectRegistry:
    return request.app.state.registry  # type: ignore[no-any-return]


async def _resolve_project_path(project_id: str, registry: ProjectRegistry) -> Path:
    """Return project_path or raise 404."""
    project = await registry.get(project_id)
    if project is None:
        raise HTTPException(status_code=404, detail=f"project {project_id!r} not found")
    return Path(project.path)


# ---------------------------------------------------------------------------
# Path validation
# ---------------------------------------------------------------------------


def _validate_relative_path(raw: str, project_path: Path) -> Path:
    """Validate a client-supplied project-relative path and resolve it.

    Rejects empty input, backslashes, absolute paths (posix `/...` or a
    Windows drive letter `C:...`), and any `..` segment. After that
    surface-level check, resolves the candidate (following symlinks) and
    requires it stay inside the resolved project root — the real guard
    against traversal via symlinks, not just literal `..`.

    Raises ValueError with a client-safe message on any violation.
    """
    if not raw or not raw.strip():
        raise ValueError("path must not be empty")
    if "\\" in raw:
        raise ValueError("path must not contain backslashes")
    if raw.startswith("/"):
        raise ValueError("path must be relative")
    if len(raw) >= 2 and raw[1] == ":":
        raise ValueError("path must be relative")

    parts = PurePosixPath(raw).parts
    if ".." in parts:
        raise ValueError("path must not contain '..'")

    root = project_path.resolve()
    candidate = project_path / raw
    try:
        resolved = candidate.resolve()
    except OSError as exc:
        logger.error("failed to resolve path %r under %s: %s", raw, project_path, exc)
        raise ValueError("invalid path") from exc

    try:
        resolved.relative_to(root)
    except ValueError as exc:
        raise ValueError("path escapes project root") from exc

    return resolved


# ---------------------------------------------------------------------------
# Directory walk
# ---------------------------------------------------------------------------


def _walk_artifacts(base: Path, *, max_depth: int, max_entries: int) -> list[Path]:
    """Recursively collect files under base, skipping dotfiles/dirs.

    Depth-capped (levels of subdirectory below base) and entry-capped (stops
    once max_entries files are found) — a defensive limit against a
    pathological/huge output tree.
    """
    results: list[Path] = []

    def _walk(current: Path, depth: int) -> None:
        if len(results) >= max_entries:
            return
        try:
            entries = sorted(current.iterdir(), key=lambda p: p.name)
        except OSError:
            return
        for entry in entries:
            if len(results) >= max_entries:
                return
            if entry.name.startswith("."):
                continue
            if entry.is_symlink():
                # Windows 정션 포함, 확산 방지 + relative_to 크래시 방지
                continue
            if entry.is_dir():
                if depth < max_depth:
                    _walk(entry, depth + 1)
                continue
            if entry.is_file():
                results.append(entry)

    _walk(base, 0)
    return results


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------


@router.get("/artifacts", response_model=list[ArtifactEntry])
async def list_artifacts(
    project_id: str,
    dir: str = Query(default="output"),
    registry: ProjectRegistry = Depends(_get_registry),
) -> list[ArtifactEntry]:
    """List files under a project-relative directory, newest first.

    404 if the project is unknown; 400 on a path-traversal attempt. A
    nonexistent directory is NOT an error — it returns an empty list (a flow
    that hasn't produced output yet is a normal state, not a client error).
    """
    project_path = await _resolve_project_path(project_id, registry)

    try:
        target_dir = _validate_relative_path(dir, project_path)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    if not target_dir.is_dir():
        return []

    root = project_path.resolve()
    files = _walk_artifacts(target_dir, max_depth=_MAX_DEPTH, max_entries=_MAX_ENTRIES)

    scored: list[tuple[float, ArtifactEntry]] = []
    for f in files:
        try:
            st = f.stat()
        except OSError:
            continue
        try:
            # Defense in depth: _walk_artifacts already skips symlinks, but a
            # pathological case (e.g. a race, or a symlink type check quirk)
            # must not 500 — just drop the offending entry from the listing.
            rel = f.resolve().relative_to(root).as_posix()
        except ValueError:
            continue
        mtime_iso = datetime.fromtimestamp(st.st_mtime, tz=timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        )
        scored.append(
            (st.st_mtime, ArtifactEntry(path=rel, name=f.name, size=st.st_size, mtime=mtime_iso))
        )

    scored.sort(key=lambda pair: pair[0], reverse=True)
    return [entry for _, entry in scored]


@router.get("/artifacts/content", response_model=ArtifactContent)
async def get_artifact_content(
    project_id: str,
    path: str = Query(...),
    registry: ProjectRegistry = Depends(_get_registry),
) -> ArtifactContent:
    """Read a single artifact file's content.

    404 if the project or file is unknown; 400 on a path-traversal attempt.
    Binary files (a NUL byte in the first 8 KiB) are reported with
    binary=true and an empty content string rather than raising an error.
    Text content beyond 256 KiB is truncated (truncated=true).
    """
    project_path = await _resolve_project_path(project_id, registry)

    try:
        target = _validate_relative_path(path, project_path)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    if not target.is_file():
        raise HTTPException(status_code=404, detail=f"artifact {path!r} not found")

    root = project_path.resolve()
    rel = target.relative_to(root).as_posix()

    try:
        size = target.stat().st_size
        with target.open("rb") as fh:
            sniff = fh.read(_BINARY_SNIFF_BYTES)
            if b"\x00" in sniff:
                return ArtifactContent(path=rel, content="", truncated=False, binary=True, size=size)
            fh.seek(0)
            data = fh.read(_CONTENT_CAP_BYTES)
    except OSError as exc:
        logger.error("failed to read artifact %s: %s", target, exc)
        raise HTTPException(status_code=404, detail="failed to read artifact") from exc

    truncated = size > _CONTENT_CAP_BYTES
    content = data.decode("utf-8", errors="replace")
    return ArtifactContent(path=rel, content=content, truncated=truncated, binary=False, size=size)
