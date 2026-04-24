"""SOUL file scanner and Pydantic models."""

from __future__ import annotations

import re
from pathlib import Path
from typing import Optional

import frontmatter
from pydantic import BaseModel, field_validator

from golem_gateway.config import SOULS_GLOBAL_DIR, SOULS_OVERRIDE_DIR

_VALID_SOUL_ID = re.compile(r"^[A-Za-z0-9_-]+$")


class SoulSummary(BaseModel):
    """Lean model returned by the list endpoint (no content field)."""

    id: str
    name: str
    rank: str
    specialty: list[str]
    description: str


class SoulDetail(SoulSummary):
    """Full model returned by the single-SOUL endpoint (includes content)."""

    content: str


def _extract_description(body: str, max_chars: int = 200) -> str:
    """Return the first non-empty, non-heading line from the markdown body."""
    normalized = body.replace("\r\n", "\n").replace("\r", "\n")
    for line in normalized.splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith("#"):
            return stripped[:max_chars]
    return ""


def _parse_specialty(raw) -> list[str]:
    """Coerce frontmatter specialty to list[str]. Only accept list or str."""
    if raw is None:
        return []
    if isinstance(raw, str):
        return [raw]
    if isinstance(raw, list):
        return [str(s) for s in raw if s is not None and not isinstance(s, (dict, list))]
    # dict, int, bool, other → reject
    import logging
    logging.getLogger(__name__).warning(
        "unexpected specialty type %r (value=%r), dropping", type(raw).__name__, raw
    )
    return []


def _parse_soul_file(path: Path) -> Optional[SoulDetail]:
    """Parse a single SOUL .md file. Returns None on unrecoverable error."""
    soul_id = path.stem

    try:
        post = frontmatter.load(str(path), encoding="utf-8")
    except Exception:
        # Malformed file — try reading raw and treat as body-only
        try:
            raw_text = path.read_text(encoding="utf-8", errors="replace")
            post = frontmatter.Post(content=raw_text)
        except Exception:
            return None

    meta = post.metadata  # dict (may be empty if no frontmatter)
    body: str = post.content or ""

    if not meta:
        import logging
        logging.getLogger(__name__).warning(
            "SOUL %s at %s has no frontmatter — using defaults", soul_id, path
        )

    name: str = str(meta.get("name") or soul_id.capitalize())
    rank: str = str(meta.get("rank") or "unknown")
    specialty: list[str] = _parse_specialty(meta.get("specialty"))
    description: str = _extract_description(body)

    return SoulDetail(
        id=soul_id,
        name=name,
        rank=rank,
        specialty=specialty,
        description=description,
        content=body,
    )


_scan_cache: dict[str, tuple[float, list[SoulDetail]]] = {}


def _dir_mtime_fingerprint() -> float:
    """Max mtime across both SOUL dirs — changes invalidate cache."""
    mtimes: list[float] = []
    for d in (SOULS_OVERRIDE_DIR, SOULS_GLOBAL_DIR):
        if d.is_dir():
            mtimes.append(d.stat().st_mtime)
            for f in d.glob("*.md"):
                try:
                    mtimes.append(f.stat().st_mtime)
                except OSError:
                    pass
    return max(mtimes) if mtimes else 0.0


def scan_souls() -> list[SoulDetail]:
    """Scan .golem/souls/ (override) then souls/ (global).

    Project override wins: if the same basename exists in both dirs,
    the .golem/souls/ version is used.
    Results are mtime-cached to avoid re-reading all files on every request.
    """
    fingerprint = _dir_mtime_fingerprint()
    cached = _scan_cache.get("all")
    if cached and cached[0] == fingerprint:
        return cached[1]

    seen: dict[str, SoulDetail] = {}

    def _scan_dir(directory: Path) -> None:
        if not directory.is_dir():
            return
        for md_file in sorted(directory.glob("*.md")):
            soul_id = md_file.stem
            if not _VALID_SOUL_ID.match(soul_id):
                continue
            if soul_id in seen:
                # Already loaded from a higher-priority directory
                continue
            parsed = _parse_soul_file(md_file)
            if parsed is not None:
                seen[soul_id] = parsed

    # Override directory has highest priority
    _scan_dir(SOULS_OVERRIDE_DIR)
    # Global fallback
    _scan_dir(SOULS_GLOBAL_DIR)

    result = list(seen.values())
    _scan_cache["all"] = (fingerprint, result)
    return result


def get_soul_by_id(soul_id: str) -> Optional[SoulDetail]:
    """Return a single SoulDetail for the given id, or None if not found."""
    if not _VALID_SOUL_ID.match(soul_id):
        return None
    for directory in (SOULS_OVERRIDE_DIR, SOULS_GLOBAL_DIR):
        candidate = directory / f"{soul_id}.md"
        if not candidate.is_file():
            continue
        # Defense in depth: ensure resolved path stays inside the directory
        try:
            if candidate.resolve().parent != directory.resolve():
                continue
        except OSError:
            continue
        return _parse_soul_file(candidate)
    return None
