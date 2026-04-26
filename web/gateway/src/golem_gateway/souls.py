"""SOUL file scanner and Pydantic models."""

from __future__ import annotations

import re
from pathlib import Path
from typing import Literal, Optional

import frontmatter
from pydantic import BaseModel

_VALID_SOUL_ID = re.compile(r"^[A-Za-z0-9_-]+$")

# Coordinator 도구 집합 — soul-parser.sh:126-128과 동일
_COORDINATOR_TOOLS = [
    "Agent", "SendMessage", "TaskCreate", "TaskStop", "Read", "Grep", "Glob"
]
# Coordinator에게 금지되는 실행 도구 — soul-parser.sh:128
_COORDINATOR_DISALLOWED_TOOLS = [
    "Edit", "Write", "Bash", "FileEdit", "FileWrite", "NotebookEdit"
]

# Rank 기반 기본 도구 집합 — soul-parser.sh:113-120
_RANK_DEFAULT_TOOLS: dict[str, list[str]] = {
    "novice": ["Read", "Edit", "Grep", "Glob"],
    "junior": ["Read", "Edit", "Write", "Bash", "Grep", "Glob"],
    "senior": ["Read", "Edit", "Write", "Bash", "Grep", "Glob", "Agent", "WebFetch"],
    "lead":   ["Read", "Edit", "Write", "Bash", "Grep", "Glob", "Agent", "WebFetch", "SendMessage"],
    "master": ["Read", "Edit", "Write", "Bash", "Grep", "Glob", "Agent", "WebFetch", "SendMessage", "TaskCreate"],
}

# Rank 기반 maxTurns 기본값 — soul-parser.sh:134-139
_RANK_DEFAULT_MAX_TURNS: dict[str, int] = {
    "novice": 15, "junior": 25, "senior": 40, "lead": 60, "master": 80,
}

# Rank 기반 isolation 기본값 — soul-parser.sh:141-148
_RANK_DEFAULT_ISOLATION: dict[str, Literal["none", "worktree"]] = {
    "novice": "none", "junior": "none",
}


class SoulSummary(BaseModel):
    """Lean model returned by the list endpoint (no content field)."""

    id: str
    name: str
    rank: str
    specialty: list[str]
    description: str


class SoulDetail(SoulSummary):
    """Full model returned by the single-SOUL endpoint (includes content).

    확장 필드(tools, disallowed_tools, max_turns, isolation, is_coordinator, effort)는
    soul-parser.sh의 rank 기반 기본값 + frontmatter 오버라이드 로직을 Python으로 미러링한다.
    """

    content: str
    tools: list[str] = []
    disallowed_tools: list[str] = []
    max_turns: Optional[int] = None
    isolation: Literal["none", "worktree"] = "none"
    is_coordinator: bool = False
    effort: Optional[Literal["low", "medium", "high"]] = None


def _parse_tools_field(raw) -> list[str]:
    """frontmatter tools 필드를 list[str]로 변환. csv 문자열 또는 yaml list 모두 처리."""
    if raw is None:
        return []
    if isinstance(raw, list):
        return [str(t).strip() for t in raw if t is not None]
    if isinstance(raw, str):
        return [t.strip() for t in raw.split(",") if t.strip()]
    return []


def _resolve_tools(
    raw_tools: list[str],
    rank: str,
    role: str,
    is_coordinator: bool,
) -> list[str]:
    """soul-parser.sh:112-121 로직 미러: rank 기본값 → frontmatter 오버라이드 → director 강제.

    director(is_coordinator=True)이면 frontmatter tools를 무시하고
    _COORDINATOR_TOOLS로 강제한다 (soul-parser.sh:126-128).
    """
    if is_coordinator or role.lower() == "director":
        return list(_COORDINATOR_TOOLS)
    if raw_tools:
        return raw_tools
    return list(_RANK_DEFAULT_TOOLS.get(rank.lower(), []))


def _resolve_disallowed_tools(raw: list[str], is_coordinator: bool) -> list[str]:
    """director이면 soul-parser.sh:128의 disallowed 목록을 강제."""
    if is_coordinator:
        return list(_COORDINATOR_DISALLOWED_TOOLS)
    return raw


def _resolve_max_turns(raw: Optional[int], rank: str, role: str) -> Optional[int]:
    """soul-parser.sh:134-139 rank 기본값 미러. frontmatter 명시 시 우선."""
    if raw is not None:
        return raw
    if role.lower() == "director":
        return 50
    return _RANK_DEFAULT_MAX_TURNS.get(rank.lower())


def _resolve_isolation(
    raw: Optional[str], rank: str, role: str
) -> Literal["none", "worktree"]:
    """soul-parser.sh:141-148 isolation 기본값 미러."""
    if raw in ("none", "worktree"):
        return raw  # type: ignore[return-value]
    if role.lower() in ("director", "qa-tester"):
        return "none"
    return _RANK_DEFAULT_ISOLATION.get(rank.lower(), "worktree")


def _resolve_effort(
    raw: Optional[str], model: str
) -> Optional[Literal["low", "medium", "high"]]:
    """soul-parser.sh:149-152 model 기반 effort 기본값 미러."""
    if raw in ("low", "medium", "high"):
        return raw  # type: ignore[return-value]
    mapping: dict[str, Literal["low", "medium", "high"]] = {
        "haiku": "low", "sonnet": "medium", "opus": "high"
    }
    for key, val in mapping.items():
        if key in model.lower():
            return val
    return "medium"


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
    role: str = str(meta.get("role") or "")
    specialty: list[str] = _parse_specialty(meta.get("specialty"))
    description: str = _extract_description(body)
    model: str = str(meta.get("model") or "")

    # 확장 필드 파싱 — soul-parser.sh Phase 1 필드와 1:1 대응
    raw_tools = _parse_tools_field(meta.get("tools"))
    raw_disallowed = _parse_tools_field(meta.get("disallowed_tools"))
    raw_max_turns: Optional[int] = None
    if meta.get("maxTurns") is not None:
        try:
            raw_max_turns = int(meta["maxTurns"])
        except (ValueError, TypeError):
            pass

    # is_coordinator: frontmatter 명시 우선, 없으면 role==director 추론
    raw_is_coordinator = meta.get("is_coordinator")
    if isinstance(raw_is_coordinator, bool):
        is_coordinator = raw_is_coordinator
    elif isinstance(raw_is_coordinator, str):
        is_coordinator = raw_is_coordinator.lower() == "true"
    else:
        is_coordinator = role.lower() == "director"

    tools = _resolve_tools(raw_tools, rank, role, is_coordinator)
    disallowed_tools = _resolve_disallowed_tools(raw_disallowed, is_coordinator)
    max_turns = _resolve_max_turns(raw_max_turns, rank, role)
    isolation = _resolve_isolation(meta.get("isolation"), rank, role)
    effort = _resolve_effort(meta.get("effort"), model)

    return SoulDetail(
        id=soul_id,
        name=name,
        rank=rank,
        specialty=specialty,
        description=description,
        content=body,
        tools=tools,
        disallowed_tools=disallowed_tools,
        max_turns=max_turns,
        isolation=isolation,
        is_coordinator=is_coordinator,
        effort=effort,
    )


_scan_cache: dict[Path, tuple[float, list[SoulDetail]]] = {}


def _dir_mtime_fingerprint(project_path: Path) -> float:
    """Max mtime across both SOUL dirs for the given project — changes invalidate cache."""
    override_dir = project_path / ".golem" / "souls"
    global_dir = project_path / "souls"
    mtimes: list[float] = []
    for d in (override_dir, global_dir):
        if d.is_dir():
            mtimes.append(d.stat().st_mtime)
            for f in d.glob("*.md"):
                try:
                    mtimes.append(f.stat().st_mtime)
                except OSError:
                    pass
    return max(mtimes) if mtimes else 0.0


def scan_souls(project_path: Path) -> list[SoulDetail]:
    """Scan {project_path}/.golem/souls/ (override) then {project_path}/souls/ (global).

    Project override wins: if the same basename exists in both dirs,
    the .golem/souls/ version is used.
    Results are mtime-cached per project_path to avoid re-reading all files on every request.
    If neither soul directory exists, returns an empty list without error.
    """
    resolved = project_path.resolve()
    fingerprint = _dir_mtime_fingerprint(resolved)
    cached = _scan_cache.get(resolved)
    if cached and cached[0] == fingerprint:
        return cached[1]

    override_dir = resolved / ".golem" / "souls"
    global_dir = resolved / "souls"

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
    _scan_dir(override_dir)
    # Global fallback
    _scan_dir(global_dir)

    result = list(seen.values())
    _scan_cache[resolved] = (fingerprint, result)
    return result


def get_soul_by_id(project_path: Path, soul_id: str) -> Optional[SoulDetail]:
    """Return a single SoulDetail for the given id within the given project, or None."""
    if not _VALID_SOUL_ID.match(soul_id):
        return None
    resolved = project_path.resolve()
    override_dir = resolved / ".golem" / "souls"
    global_dir = resolved / "souls"
    for directory in (override_dir, global_dir):
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
