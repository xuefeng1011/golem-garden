"""Gateway configuration: server constants."""

from __future__ import annotations

import os
import shutil
from pathlib import Path


# ---------------------------------------------------------------------------
# Bash bridge resolution (Git Bash vs WSL)
# ---------------------------------------------------------------------------
#
# The gateway shells out to forge.sh via bash. On Windows the bare name "bash"
# resolves through PATH and very often hits C:\Windows\System32\bash.exe — the
# WSL launcher — which (a) needs /mnt/<drive>/ paths and (b) fails entirely if
# WSL is not installed/healthy. Git Bash (MSYS2, shipped with Git for Windows)
# is the bash GolemGarden actually targets and uses /<drive>/ mount paths.
#
# We therefore resolve an explicit bash binary, preferring Git Bash, and derive
# the matching mount style so to_bash_path() emits paths that bash understands.
# Overrides: GOLEM_BASH_BIN (executable), GOLEM_BASH_MOUNT ("msys"|"wsl"|"posix").


def _resolve_bash() -> tuple[str, str]:
    """Return (bash_executable, mount_style).

    mount_style: "msys" → /c/...  | "wsl" → /mnt/c/...  | "posix" → unchanged.
    """
    override = os.environ.get("GOLEM_BASH_BIN")
    if override:
        return override, os.environ.get("GOLEM_BASH_MOUNT", "msys")

    if os.name != "nt":
        return (shutil.which("bash") or "/bin/bash"), "posix"

    # Windows: prefer Git Bash over WSL. Search well-known install locations
    # plus a path derived from the resolved `git` executable.
    candidates: list[str] = [
        r"C:\Program Files\Git\bin\bash.exe",
        r"C:\Program Files\Git\usr\bin\bash.exe",
        r"C:\Program Files (x86)\Git\bin\bash.exe",
    ]
    git = shutil.which("git")
    if git:
        # .../Git/cmd/git.exe → .../Git ; .../Git/bin/git.exe → .../Git
        git_root = Path(git).parent.parent
        candidates.append(str(git_root / "bin" / "bash.exe"))
        candidates.append(str(git_root / "usr" / "bin" / "bash.exe"))
    for cand in candidates:
        if Path(cand).is_file():
            return cand, "msys"

    # Fallback: whatever `bash` PATH resolution finds. If it is the System32
    # WSL launcher, mark it as WSL so paths get /mnt/ form.
    which_bash = shutil.which("bash")
    if which_bash:
        mount = "wsl" if "system32" in which_bash.lower() else "msys"
        return which_bash, mount

    return "bash", "msys"


BASH_BIN, _BASH_MOUNT = _resolve_bash()
_BASH_MOUNT = os.environ.get("GOLEM_BASH_MOUNT", _BASH_MOUNT)


def to_bash_path(p: Path | str) -> str:
    """Convert a Windows path to the form the resolved bash understands.

    Git Bash (MSYS2) mounts drives at /<drive>/ (e.g. /c/foo); WSL uses
    /mnt/<drive>/ (e.g. /mnt/c/foo). The mount style is detected from the
    resolved bash binary (_resolve_bash) and overridable via GOLEM_BASH_MOUNT.
    On non-Windows / posix bash the path is returned unchanged.

    Native Windows forms like 'C:/foo' silently fail with 'No such file or
    directory' from MSYS bash, so callers must pass results of this function.
    Non-ASCII path components work in Git Bash directly; if a particular setup
    hits codepage issues, set GOLEM_FORGE_SH_BASH to an ASCII junction path.
    """
    if os.name != "nt" or _BASH_MOUNT == "posix":
        return str(p)
    s = (p.as_posix() if isinstance(p, Path) else str(p).replace("\\", "/"))
    if len(s) > 2 and s[1] == ":" and s[2] == "/":
        drive = s[0].lower()
        if _BASH_MOUNT == "wsl":
            return "/mnt/" + drive + s[2:]
        return "/" + drive + s[2:]  # msys (Git Bash): /c/...
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
    # REMOVED: "--no-session-persistence" — we now use --session-id/--resume natively
    # so claude maintains conversation context across turns and we get cache hits
    # on subsequent turns. See session_manager.spawn_run for the decision tree.
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

# Long-form orchestration commands (flow run / mission run) get a higher
# ceiling: a DAG of N agent steps legitimately exceeds the single-command cap,
# and killing mid-flow used to strand steps in "running" (permanent stall).
# Per-step runaway is still bounded by agent-runner's effort-based timeout.
MAX_FLOW_SECONDS: int = int(os.environ.get("GOLEM_MAX_FLOW_SECONDS", "1800"))

# Maximum combined stdout+stderr bytes per forge run before termination.
FORGE_OUTPUT_CAP_BYTES: int = 2 * 1024 * 1024  # 2 MB

# Whitelisted forge subcommands.  Anything outside this set is rejected 400.
ALLOWED_FORGE_COMMANDS: frozenset[str] = frozenset({
    "status", "souls", "rank", "dashboard", "insights",
    "build", "quick", "assign", "review", "sync",
    "mailbox", "session", "recover-history", "worktree",
    "memory", "retro", "chemistry", "achievement", "skill-tree",
    "dna", "budget", "tool-char",
    "skill-export", "skill-import",
    "soul-create", "pack",
    "log-add",
    "overview", "ov",
    "flow",
    "mission",
})

# ---------------------------------------------------------------------------
# Phase A: Run trajectory persistence (OBSERVABILITY_PLAN)
# ---------------------------------------------------------------------------

# Number of completed runs to keep per project (rolling GC).
RUNS_KEEP: int = int(os.environ.get("GOLEM_RUNS_KEEP", "200"))

# Per-run raw JSONL byte cap (512 KiB).
RUN_RAW_CAP_BYTES: int = 512 * 1024

# Set to "1" to disable all run persistence (useful for CI/testing).
RUNS_DISABLE: bool = os.environ.get("GOLEM_RUNS_DISABLE") == "1"
