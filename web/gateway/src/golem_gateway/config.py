"""Gateway configuration: server constants."""

from __future__ import annotations

import os
import shutil
from pathlib import Path


def to_bash_path(p: Path | str) -> str:
    """Convert a Windows-style path to /mnt/<drive>/... form for Git for
    Windows / WSL bash. On non-Windows platforms returns the path unchanged.

    Background: Python's subprocess on Windows passes argv as Unicode via
    CreateProcessW, but Git for Windows bash (the bash that ships with the
    Git installer and is what shutil.which('bash') typically finds) interprets
    argv via its own MSYS path translator. Native Windows forms like
    'C:/foo/bar' silently fail with 'No such file or directory' from this
    bash; '/mnt/c/foo/bar' works. Korean (or any non-ASCII) characters in the
    path additionally trigger codepage conversion bugs — we mitigate that with
    GOLEM_FORGE_SH env override (see FORGE_SH_PATH).
    """
    if os.name != "nt":
        return str(p)
    s = (p.as_posix() if isinstance(p, Path) else str(p).replace("\\", "/"))
    if len(s) > 2 and s[1] == ":" and s[2] == "/":
        return "/mnt/" + s[0].lower() + s[2:]
    return s

# Server
HOST: str = "127.0.0.1"
PORT: int = 8642

# CORS allowed origins
CORS_ORIGINS: list[str] = [
    "http://localhost:5173",
    "http://localhost:8648",
]

# ---------------------------------------------------------------------------
# Phase 2: Claude Code subprocess bridge
# ---------------------------------------------------------------------------

# Resolved path to the `claude` executable.
# On Windows, shutil.which("claude") returns the .cmd wrapper which cannot be
# exec'd directly by asyncio.create_subprocess_exec without shell=True.
# We resolve to the underlying .exe by:
#   1. Checking if the .cmd sits next to a .exe of the same stem, or
#   2. Reading the .cmd to find the real binary path.
# Falls back to the .cmd path if no .exe is found (session_manager will route
# through cmd /c in that case).
def _resolve_claude_cmd() -> str | None:
    """Return the best executable path for the claude CLI."""
    import re as _re
    cmd_path = shutil.which("claude")
    if cmd_path is None:
        return None
    cmd_path_lower = cmd_path.lower()
    if not (cmd_path_lower.endswith(".cmd") or cmd_path_lower.endswith(".bat")):
        return cmd_path  # Already a real binary
    # Try reading the .cmd to find the .exe it delegates to.
    # The .cmd may use %dp0% (the script's own directory) — substitute it.
    try:
        cmd_dir = Path(cmd_path).parent
        text = Path(cmd_path).read_text(encoding="utf-8", errors="replace")
        match = _re.search(r'"([^"]+\.exe)"', text)
        if match:
            raw_exe = match.group(1)
            # Expand %dp0% / %~dp0 to the cmd file's directory.
            # Use a lambda so the replacement string isn't parsed for escapes.
            cmd_dir_str = str(cmd_dir)
            expanded = _re.sub(
                r'%~?dp0%?\\?',
                lambda _m: cmd_dir_str + "\\",
                raw_exe,
                flags=_re.IGNORECASE,
            )
            exe_path = Path(expanded)
            if exe_path.is_file():
                return str(exe_path)
    except OSError:
        pass
    # Fallback: same directory, same stem, .exe extension
    stem_exe = Path(cmd_path).with_suffix(".exe")
    if stem_exe.is_file():
        return str(stem_exe)
    # Unable to resolve a real .exe — return None so callers fail cleanly
    # rather than falling back to a cmd.exe shell invocation (injection risk).
    return None


CLAUDE_CMD: str | None = _resolve_claude_cmd()

if CLAUDE_CMD is None:
    import logging as _logging
    _logging.getLogger(__name__).error(
        "claude CLI not found or could not be resolved to a .exe — "
        "POST /v1/runs will return 500"
    )

# CLI flags always prepended to every Claude Code invocation.
CLAUDE_ARGS_BASE: list[str] = [
    "--print",
    "--output-format=stream-json",
    "--verbose",
    "--no-session-persistence",
]

# Async queue max depth per run; excess events are dropped with a WARNING log.
RUN_QUEUE_MAXSIZE: int = 1000

# Maximum wall-clock seconds before a run is forcibly terminated.
MAX_RUN_SECONDS: int = 300

# Maximum accepted input size in bytes (32 KiB).
INPUT_MAX_BYTES: int = 32 * 1024

# ---------------------------------------------------------------------------
# Phase 6: Forge runner
# ---------------------------------------------------------------------------

# Path to the forge.sh script installed by GolemGarden (Windows path form).
FORGE_SH_PATH: Path = Path(
    os.environ.get("GOLEM_FORGE_SH")
    or str(Path.home() / ".claude" / "golem-garden" / "forge.sh")
)

# Bash-friendly form of the same path. Users with non-ASCII home dirs
# should set GOLEM_FORGE_SH_BASH to an explicit ASCII path (e.g.
# /mnt/c/g-garden/forge.sh) backed by an `mklink /J C:\g-garden ...` junction.
FORGE_SH_BASH_PATH: str = (
    os.environ.get("GOLEM_FORGE_SH_BASH")
    or to_bash_path(FORGE_SH_PATH)
)

if not FORGE_SH_PATH.is_file():
    import logging as _logging
    _logging.getLogger(__name__).error(
        "forge.sh not found at %s — POST /v1/projects/{id}/forge will return 500",
        FORGE_SH_PATH,
    )

# Maximum wall-clock seconds before a forge run is forcibly terminated.
MAX_FORGE_SECONDS: int = 300

# Maximum combined stdout+stderr bytes per forge run before termination.
FORGE_OUTPUT_CAP_BYTES: int = 2 * 1024 * 1024  # 2 MB

# Whitelisted forge subcommands.  Anything outside this set is rejected 400.
ALLOWED_FORGE_COMMANDS: frozenset[str] = frozenset({
    "status", "souls", "rank", "dashboard", "insights",
    "build", "quick", "assign", "review", "sync",
    "mailbox", "session", "recover", "worktree",
    "memory", "retro", "chemistry", "achievement", "skill-tree",
    "dna", "budget", "tool-char",
    "skill-export", "skill-import",
    "soul-create", "pack",
    "log-add",
    "overview", "ov",
})
