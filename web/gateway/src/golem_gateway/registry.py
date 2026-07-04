"""Project registry: load/save ~/.golem/projects.json with atomic writes."""

from __future__ import annotations

import asyncio
import json
import logging
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal
from uuid import uuid4

from pydantic import BaseModel

logger = logging.getLogger(__name__)


def _registry_path() -> Path:
    return Path.home() / ".golem" / "projects.json"


def _validate_project_path(p: str, *, allow_missing: bool = False) -> Path:
    """Validate a project path before registering. Returns resolved Path or raises ValueError.

    Zen F1: tightened allowlist. The path MUST live under ``Path.home()`` and be
    an existing directory.  The marker (``.golem/`` or ``souls/``) check used
    previously is removed from validation — pre-creating ``.golem/`` inside a
    system path was a trivial bypass.

    ``allow_missing=True`` (studio 생성 경로): 아직 없는 폴더를 허용한다 —
    위치 정책(home / GOLEM_EXTRA_PROJECT_ROOTS)은 동일하게 적용되고,
    파일이 이미 있는 경로는 여전히 거부된다. 디렉토리 생성은 호출자 몫.

    Escape hatch: ``GOLEM_EXTRA_PROJECT_ROOTS`` is an ``os.pathsep``-separated
    list of additional roots that are explicitly trusted.  This is opt-in and
    must be configured by the operator launching the Gateway.
    """
    if not p or not p.strip():
        raise ValueError("path is empty")
    resolved = Path(p).expanduser().resolve()
    if not resolved.is_dir():
        if not allow_missing:
            raise ValueError(f"path does not exist or is not a directory: {resolved}")
        if resolved.exists():
            raise ValueError(f"path exists but is not a directory: {resolved}")

    home = Path.home().resolve()

    # Default policy: must live under the user's home directory.
    try:
        resolved.relative_to(home)
        return resolved
    except ValueError:
        pass

    # Escape hatch: explicit env-var allowlist of additional roots.
    extra_roots_env = os.environ.get("GOLEM_EXTRA_PROJECT_ROOTS", "").strip()
    if extra_roots_env:
        for raw in extra_roots_env.split(os.pathsep):
            raw = raw.strip()
            if not raw:
                continue
            try:
                root = Path(raw).expanduser().resolve()
                resolved.relative_to(root)
                return resolved
            except (ValueError, OSError):
                continue

    raise ValueError(
        f"path must be inside Path.home() ({home}); "
        f"set GOLEM_EXTRA_PROJECT_ROOTS to allow other roots: {resolved}"
    )


class Project(BaseModel):
    id: str
    name: str
    path: str
    created_at: str
    kind: Literal["project", "studio"] = "project"


class ProjectRegistry:
    def __init__(self) -> None:
        self._projects: list[Project] = []
        self._lock = asyncio.Lock()
        self._loaded = False

    async def load(self) -> None:
        async with self._lock:
            await self._load_unlocked()

    async def _load_unlocked(self) -> None:
        p = _registry_path()
        if not p.is_file():
            self._projects = []
            self._loaded = True
            return
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
            raw = data.get("projects", []) if isinstance(data, dict) else []
            self._projects = [Project.model_validate(it) for it in raw]
        except Exception as e:
            logger.error("failed to load registry %s: %s", p, e)
            self._projects = []
        self._loaded = True

    async def _save_unlocked(self) -> None:
        p = _registry_path()
        p.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "version": 1,
            "projects": [proj.model_dump() for proj in self._projects],
        }
        tmp = p.with_suffix(".json.tmp")
        tmp.write_text(
            json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8"
        )
        os.replace(tmp, p)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    async def list(self, *, kind: Literal["project", "studio"] | None = None) -> list[Project]:
        async with self._lock:
            if not self._loaded:
                await self._load_unlocked()
            # F5: hand out copies so caller mutation cannot corrupt registry state.
            return [
                p.model_copy() for p in self._projects if kind is None or p.kind == kind
            ]

    async def get(self, project_id: str) -> Project | None:
        async with self._lock:
            if not self._loaded:
                await self._load_unlocked()
            for proj in self._projects:
                if proj.id == project_id:
                    # F5: copy on read for the same reason as list().
                    return proj.model_copy()
        return None

    async def create(
        self,
        *,
        name: str,
        path: str,
        kind: Literal["project", "studio"] = "project",
        create_missing: bool = False,
    ) -> Project:
        """Create a new project entry.

        ``create_missing=True`` (studio): 허용 루트 정책을 통과한 경로가
        아직 없으면 디렉토리를 생성한다 — 스튜디오는 "새 폴더 지정" UX.

        Raises:
            ValueError: if name is empty/too long, path is invalid (missing,
                outside the allowlist), or path is duplicate.
        """
        # Validate name
        name = name.strip()
        if not name:
            raise ValueError("name must be non-empty")
        if len(name) > 100:
            raise ValueError("name must be ≤100 characters")

        # F3: validate + allowlist path BEFORE storing.
        resolved = _validate_project_path(path, allow_missing=create_missing)
        if create_missing and not resolved.is_dir():
            try:
                resolved.mkdir(parents=True, exist_ok=True)
            except OSError as exc:
                raise ValueError(f"failed to create directory {resolved}: {exc}") from exc

        canonical = resolved.as_posix().casefold()

        now_iso = datetime.now(tz=timezone.utc).isoformat().replace("+00:00", "Z")
        new_project = Project(
            id=str(uuid4()),
            name=name,
            path=str(resolved),
            created_at=now_iso,
            kind=kind,
        )

        async with self._lock:
            if not self._loaded:
                await self._load_unlocked()

            # Duplicate path check (case-insensitive)
            for proj in self._projects:
                existing_canonical = Path(proj.path).resolve().as_posix().casefold()
                if existing_canonical == canonical:
                    raise ValueError(
                        f"path {path!r} is already registered (id={proj.id!r})"
                    )

            self._projects.append(new_project)
            await self._save_unlocked()

        return new_project

    async def delete(self, project_id: str) -> bool:
        """Remove a project by id. Returns True if found and removed, False if not found."""
        async with self._lock:
            if not self._loaded:
                await self._load_unlocked()
            before = len(self._projects)
            self._projects = [p for p in self._projects if p.id != project_id]
            if len(self._projects) == before:
                return False
            await self._save_unlocked()
        return True
