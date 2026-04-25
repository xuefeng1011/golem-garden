"""Helpers to locate and clean up claude CLI's per-session files.

claude CLI persists session state under ~/.claude/projects/<sanitized_cwd>/
when --session-id or --resume is used (no --no-session-persistence).
We only own the lifecycle insofar as: when our SQLite session row goes
away (via DELETE), the corresponding claude session file should also go
away.  Otherwise claude session files accumulate forever.

## Observed layout (Windows + Git-Bash):

    ~/.claude/projects/<sanitized>/
        <uuid>.jsonl          ← main session transcript
        <uuid>/               ← subdir with subagent tool results (optional)
            subagents/
            tool-results/
        memory/               ← project-level memory (not UUID-named, never touched)

Sanitization rule (observed): resolve absolute path as POSIX string, then
replace every run of non-alphanumeric characters with a single hyphen,
strip leading/trailing hyphens.

Examples:
    C:/01-xuefeng/08-ai/golem-garden  →  C--01-xuefeng-08-ai-golem-garden
    /home/user/my project             →  home-user-my-project
"""

from __future__ import annotations

import logging
import re
from pathlib import Path

logger = logging.getLogger(__name__)

# UUID v4 pattern — only delete files whose stem matches this.
_UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
    re.IGNORECASE,
)


def _sanitize_cwd(project_path: Path) -> str:
    """Mirror claude CLI's sanitization of cwd for the projects subdir name.

    Observed rule: absolute POSIX path → replace non-alphanumeric runs with
    hyphens → strip leading/trailing hyphens.
    """
    s = project_path.resolve().as_posix()
    return re.sub(r"[^A-Za-z0-9]+", "-", s).strip("-")


def claude_sessions_dir(project_path: Path) -> Path:
    """Return ~/.claude/projects/<sanitized>/ for the given project."""
    return Path.home() / ".claude" / "projects" / _sanitize_cwd(project_path)


def delete_claude_session(project_path: Path, session_id: str) -> bool:
    """Best-effort deletion of claude's per-session file.

    Returns True if a file was deleted, False if none existed.
    Never raises — claude's storage layout could change between versions.
    Only deletes UUID-named .jsonl files; never touches memory/ or other
    non-UUID entries.
    """
    if not _UUID_RE.match(session_id):
        logger.warning("delete_claude_session: %r does not look like a UUID, skipping", session_id)
        return False

    sessions_dir = claude_sessions_dir(project_path)
    if not sessions_dir.is_dir():
        return False

    # Observed naming: <uuid>.jsonl at top level; subdir <uuid>/ is metadata
    # (subagents/, tool-results/) — we don't touch subdirs.
    candidates = [
        sessions_dir / f"{session_id}.jsonl",
        # Fallback in case claude ever nests under sessions/
        sessions_dir / "sessions" / f"{session_id}.jsonl",
        sessions_dir / f"{session_id}.json",
    ]
    for path in candidates:
        if path.is_file():
            try:
                path.unlink()
                logger.info("deleted claude session file: %s", path)
                return True
            except OSError as e:
                logger.warning("failed to delete claude session file %s: %s", path, e)
    return False


def gc_orphaned_claude_sessions(project_path: Path, known_session_ids: set[str]) -> int:
    """Delete claude session files whose UUIDs are NOT in known_session_ids.

    Only considers top-level .jsonl files whose stem matches a UUID pattern.
    Never touches memory/, non-UUID files, or subdirectories.
    Used by the cleanup endpoint or a startup hook.
    Returns count deleted.  Never raises.
    """
    sessions_dir = claude_sessions_dir(project_path)
    if not sessions_dir.is_dir():
        return 0

    deleted = 0
    try:
        entries = list(sessions_dir.iterdir())
    except OSError as e:
        logger.warning("gc_orphaned_claude_sessions: cannot list %s: %s", sessions_dir, e)
        return 0

    for entry in entries:
        if not entry.is_file() or entry.suffix != ".jsonl":
            continue
        stem = entry.stem
        if not _UUID_RE.match(stem):
            # Not a UUID-named file — never delete (e.g. memory artifacts)
            continue
        if stem in known_session_ids:
            continue
        try:
            entry.unlink()
            deleted += 1
            logger.info("GC: deleted orphaned claude session %s", stem)
        except OSError as e:
            logger.warning("GC: failed to delete %s: %s", entry, e)
    return deleted
