"""Skill file scanner and Pydantic models."""

from __future__ import annotations

import re
from pathlib import Path
from typing import Optional

import frontmatter
from pydantic import BaseModel

_VALID_SKILL_ID = re.compile(r"^[A-Za-z0-9_-]+$")


class SkillSummary(BaseModel):
    """Lean model returned by the list endpoint (no content field)."""

    id: str
    name: str
    description: str


class SkillDetail(SkillSummary):
    """Full model returned by the single-skill endpoint (includes content)."""

    content: str
    has_scripts: bool


def _first_nonempty_line(body: str, max_chars: int = 200) -> str:
    """Return the first non-empty, non-heading line from the markdown body."""
    normalized = body.replace("\r\n", "\n").replace("\r", "\n")
    for line in normalized.splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith("#"):
            return stripped[:max_chars]
    return ""


def _parse_skill_file(path: Path, skill_dir: Path) -> Optional[SkillDetail]:
    """Parse a single SKILL.md file. Returns None on unrecoverable error."""
    try:
        post = frontmatter.load(str(path), encoding="utf-8")
    except Exception:
        try:
            raw = path.read_text(encoding="utf-8", errors="replace")
            post = frontmatter.Post(content=raw)
        except Exception:
            return None

    meta = post.metadata
    body: str = post.content or ""
    skill_id = skill_dir.name
    name = str(meta.get("name") or skill_id)
    description = str(meta.get("description") or _first_nonempty_line(body)).strip()
    has_scripts = any(p.is_file() and p.suffix != ".md" for p in skill_dir.iterdir())

    return SkillDetail(
        id=skill_id,
        name=name,
        description=description,
        content=body,
        has_scripts=has_scripts,
    )


_scan_cache: dict[Path, tuple[float, list[SkillDetail]]] = {}


def _dir_mtime_fingerprint(project_path: Path) -> float:
    """Max mtime across both skill dirs for the given project — changes invalidate cache."""
    claude_skills_dir = project_path / ".claude" / "skills"
    legacy_dir = project_path / "skills"
    mtimes: list[float] = []
    for d in (claude_skills_dir, legacy_dir):
        if d.is_dir():
            mtimes.append(d.stat().st_mtime)
            for skill_dir in d.iterdir():
                try:
                    mtimes.append(skill_dir.stat().st_mtime)
                except OSError:
                    pass
                skill_md = skill_dir / "SKILL.md"
                if skill_md.is_file():
                    try:
                        mtimes.append(skill_md.stat().st_mtime)
                    except OSError:
                        pass
    return max(mtimes) if mtimes else 0.0


def scan_skills(project_path: Path) -> list[SkillDetail]:
    """Scan .claude/skills/ (priority) then skills/ (fallback).

    Override wins: if same basename exists in both, .claude/skills/ wins.
    Results are mtime-cached per project_path to avoid re-reading all files on every request.
    If neither skill directory exists, returns an empty list without error.
    """
    resolved = project_path.resolve()
    fingerprint = _dir_mtime_fingerprint(resolved)
    cached = _scan_cache.get(resolved)
    if cached and cached[0] == fingerprint:
        return cached[1]

    claude_skills_dir = resolved / ".claude" / "skills"
    legacy_dir = resolved / "skills"

    seen: dict[str, SkillDetail] = {}

    for base in (claude_skills_dir, legacy_dir):
        if not base.is_dir():
            continue
        for skill_dir in sorted(base.iterdir()):
            if not skill_dir.is_dir():
                continue
            skill_id = skill_dir.name
            if not _VALID_SKILL_ID.match(skill_id):
                continue
            if skill_id in seen:
                # Already loaded from a higher-priority directory
                continue
            skill_md = skill_dir / "SKILL.md"
            if not skill_md.is_file():
                continue
            parsed = _parse_skill_file(skill_md, skill_dir)
            if parsed is not None:
                seen[skill_id] = parsed

    result = list(seen.values())
    _scan_cache[resolved] = (fingerprint, result)
    return result


def get_skill_by_id(project_path: Path, skill_id: str) -> Optional[SkillDetail]:
    """Return a single SkillDetail for the given id within the given project, or None."""
    if not _VALID_SKILL_ID.match(skill_id):
        return None
    resolved = project_path.resolve()
    claude_skills_dir = resolved / ".claude" / "skills"
    legacy_dir = resolved / "skills"
    for base in (claude_skills_dir, legacy_dir):
        candidate = base / skill_id / "SKILL.md"
        if not candidate.is_file():
            continue
        # Defense in depth: resolved path must be inside base / skill_id
        try:
            if candidate.resolve().parent.parent != base.resolve():
                continue
        except OSError:
            continue
        return _parse_skill_file(candidate, candidate.parent)
    return None
