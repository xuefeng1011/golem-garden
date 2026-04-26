"""ForgeRunner — spawn and drain forge.sh subprocesses.

Keeps forge runs completely separate from SessionManager (which owns claude
subprocesses).  One ForgeRun per invocation; single-consumer SSE queue.
"""

from __future__ import annotations

import asyncio
import logging
import os
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Literal

from pydantic import BaseModel

from golem_gateway.config import (
    ALLOWED_FORGE_COMMANDS,
    FORGE_OUTPUT_CAP_BYTES,
    FORGE_SH_BASH_PATH,
    FORGE_SH_PATH,
    MAX_FORGE_SECONDS,
    to_bash_path,
)

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Event model
# ---------------------------------------------------------------------------

class ForgeEvent(BaseModel):
    event: Literal["forge.stdout", "forge.stderr", "forge.completed", "forge.failed"]
    run_id: str
    line: str | None = None
    exit_code: int | None = None
    duration_ms: int | None = None
    reason: str | None = None


# Terminal events — must never be evicted from the queue.
_TERMINAL_FORGE_EVENTS: frozenset[str] = frozenset({"forge.completed", "forge.failed"})

# Shell-meta characters that are forbidden in individual args (defense-in-depth;
# we use list-form subprocess so they would never be interpolated anyway).
# Zen M4: include carriage return — bash readline can split on \r on Windows.
_FORBIDDEN_ARG_CHARS: frozenset[str] = frozenset(";|&<>`$\n\r")

# Zen F5: minimal env passthrough for forge subprocesses. forge.sh is a bash
# script that does not need ANTHROPIC_API_KEY, AWS creds, npm tokens, etc.
# Only carry what bash on Windows / Unix needs to actually run.
_FORGE_ENV_KEEP: frozenset[str] = frozenset({
    # Path / shell discovery.
    "PATH", "HOME", "USERPROFILE", "USER", "USERNAME",
    "SHELL", "TERM", "COMSPEC",
    # Locale / encoding.
    "LANG", "LC_ALL", "LC_CTYPE", "TZ",
    # Temp dirs.
    "TEMP", "TMP", "TMPDIR",
    # Git for Windows / MSYS2 path-conversion guards.
    "MSYSTEM", "MSYS_NO_PATHCONV", "MSYS2_ARG_CONV_EXCL",
    # GolemGarden-specific overrides forge.sh actually consults.
    "GOLEM_PROJECT", "GOLEM_FORGE_SH", "GOLEM_FORGE_SH_BASH",
    "GOLEM_EXTRA_PROJECT_ROOTS",
})


def _build_forge_env(project_path: Path) -> dict[str, str]:
    """Build the env dict for forge subprocesses (Zen F5).

    Allowlist-based: only well-known variables flow through.  Always sets
    GOLEM_PROJECT and the MSYS path-conversion guards so forge.sh sees a sane
    environment regardless of what the operator launched the Gateway with.
    """
    base = {k: v for k, v in os.environ.items() if k in _FORGE_ENV_KEEP}
    base["GOLEM_PROJECT"] = to_bash_path(project_path)
    base["MSYS_NO_PATHCONV"] = "1"
    base["MSYS2_ARG_CONV_EXCL"] = "*"
    return base

# Per-arg length cap.
_ARG_MAX_CHARS: int = 512

# Maximum number of args.
_ARGS_MAX_COUNT: int = 30


# ---------------------------------------------------------------------------
# Data class
# ---------------------------------------------------------------------------

@dataclass
class ForgeRun:
    run_id: str
    command: str
    args: list[str]
    project_id: str
    project_path: Path
    proc: asyncio.subprocess.Process | None
    queue: asyncio.Queue[ForgeEvent]
    done: asyncio.Event
    started_at: float
    output_bytes: int = 0  # running total for output cap

    # Background task references for clean teardown.
    drain_task: asyncio.Task[None] | None = None
    stderr_task: asyncio.Task[None] | None = None
    watchdog_task: asyncio.Task[None] | None = None
    # Prevents double-emit of terminal events from drain + watchdog racing.
    terminal_emitted: bool = False
    # Single-consumer guard.
    subscribed: bool = False
    # Legacy catch-all (kept for compatibility).
    _tasks: list[asyncio.Task[None]] = field(default_factory=list)


# ---------------------------------------------------------------------------
# ForgeRunner
# ---------------------------------------------------------------------------

class ForgeRunner:
    def __init__(self) -> None:
        self._runs: dict[str, ForgeRun] = {}
        self._lock = asyncio.Lock()

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    async def spawn(
        self,
        *,
        command: str,
        args: list[str],
        project_id: str,
        project_path: Path,
    ) -> ForgeRun:
        """Validate, spawn forge.sh, and begin draining output.

        Raises:
            ValueError: command not whitelisted, or args contain forbidden content.
            RuntimeError: forge.sh path missing or subprocess fails to start.
        """
        # --- validate command ---
        if command not in ALLOWED_FORGE_COMMANDS:
            raise ValueError(
                f"forge command {command!r} is not in the allowed whitelist"
            )

        # --- validate args ---
        if len(args) > _ARGS_MAX_COUNT:
            raise ValueError(
                f"too many args: {len(args)} > {_ARGS_MAX_COUNT}"
            )
        for i, arg in enumerate(args):
            if len(arg) > _ARG_MAX_CHARS:
                raise ValueError(
                    f"arg[{i}] exceeds {_ARG_MAX_CHARS} chars"
                )
            bad = _FORBIDDEN_ARG_CHARS.intersection(arg)
            if bad:
                raise ValueError(
                    f"arg[{i}] contains forbidden characters: {sorted(bad)!r}"
                )

        # --- check forge.sh exists ---
        if not FORGE_SH_PATH.is_file():
            raise RuntimeError(
                f"forge.sh not found at {FORGE_SH_PATH} — "
                "ensure GolemGarden is installed"
            )

        run_id = str(uuid.uuid4())

        run = ForgeRun(
            run_id=run_id,
            command=command,
            args=list(args),
            project_id=project_id,
            project_path=project_path,
            proc=None,
            queue=asyncio.Queue(maxsize=2000),
            done=asyncio.Event(),
            started_at=time.monotonic(),
        )

        # Build subprocess arg list — list-form, no shell=True.
        # forge.sh is a bash script; invoke it via bash explicitly so we never
        # rely on shebang execution (which fails on some Windows setups).
        # Git for Windows bash needs /mnt/<drive>/... paths, not C:/...
        # FORGE_SH_BASH_PATH already converted (and overridable via
        # GOLEM_FORGE_SH_BASH for non-ASCII home dirs).
        subprocess_args: list[str] = [
            "bash",
            FORGE_SH_BASH_PATH,
            command,
            *args,
        ]

        # Zen F5: minimal env (allowlist) — see _build_forge_env.
        env = _build_forge_env(project_path)

        logger.info(
            "spawning forge run %s (command=%s project=%s args=%r)",
            run_id,
            command,
            project_id,
            args,
        )

        try:
            proc = await asyncio.create_subprocess_exec(
                *subprocess_args,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                stdin=asyncio.subprocess.DEVNULL,
                cwd=str(project_path),
                env=env,
            )
        except (OSError, FileNotFoundError) as exc:
            raise RuntimeError(f"failed to spawn forge subprocess: {exc}") from exc

        run.proc = proc

        async with self._lock:
            self._runs[run_id] = run

        # Start background tasks.
        run.drain_task = asyncio.create_task(
            self._drain_stdout(run), name=f"forge-drain-{run_id}"
        )
        run.stderr_task = asyncio.create_task(
            self._drain_stderr(run), name=f"forge-stderr-{run_id}"
        )
        run.watchdog_task = asyncio.create_task(
            self._watchdog(run), name=f"forge-watchdog-{run_id}"
        )
        run._tasks.extend([run.drain_task, run.stderr_task, run.watchdog_task])

        return run

    async def get_run(self, run_id: str) -> ForgeRun | None:
        return self._runs.get(run_id)

    async def terminate_run(self, run_id: str) -> None:
        """Kill subprocess, cancel tasks, evict from _runs. Idempotent."""
        async with self._lock:
            run = self._runs.pop(run_id, None)
        if run is None:
            return

        if run.proc is not None and run.proc.returncode is None:
            try:
                run.proc.terminate()
                try:
                    await asyncio.wait_for(run.proc.wait(), timeout=2.0)
                except asyncio.TimeoutError:
                    run.proc.kill()
                    await run.proc.wait()
            except ProcessLookupError:
                pass

        live_tasks = [
            t for t in (run.drain_task, run.stderr_task, run.watchdog_task)
            if t is not None and not t.done()
        ]
        for t in live_tasks:
            t.cancel()
        if live_tasks:
            await asyncio.gather(*live_tasks, return_exceptions=True)

        run.done.set()

    async def shutdown(self) -> None:
        """Terminate all live forge runs on app shutdown."""
        logger.info("ForgeRunner shutting down (%d runs)", len(self._runs))
        async with self._lock:
            run_ids = list(self._runs.keys())
        await asyncio.gather(
            *(self.terminate_run(rid) for rid in run_ids),
            return_exceptions=True,
        )

    # ------------------------------------------------------------------
    # Internal tasks
    # ------------------------------------------------------------------

    def _check_output_cap(self, run: ForgeRun) -> bool:
        """Return True if the run has exceeded FORGE_OUTPUT_CAP_BYTES.

        Side effects on cap-hit: emit a single forge.failed terminal event and
        terminate the subprocess. Idempotent — a second call after the first
        cap-hit is a no-op (terminal_emitted guards re-emit).
        """
        if run.output_bytes <= FORGE_OUTPUT_CAP_BYTES:
            return False
        if not run.terminal_emitted:
            logger.warning(
                "forge run %s exceeded output cap (%d bytes), terminating",
                run.run_id,
                FORGE_OUTPUT_CAP_BYTES,
            )
            run.terminal_emitted = True
            self._enqueue(
                run,
                ForgeEvent(
                    event="forge.failed",
                    run_id=run.run_id,
                    reason="output exceeded 2MB cap",
                ),
            )
            if run.proc is not None:
                try:
                    run.proc.terminate()
                except ProcessLookupError:
                    pass
        return True

    async def _drain_stdout(self, run: ForgeRun) -> None:
        """Read stdout lines from forge.sh and enqueue forge.stdout events."""
        assert run.proc is not None and run.proc.stdout is not None
        try:
            async for line_bytes in run.proc.stdout:
                line = line_bytes.decode("utf-8", errors="replace").rstrip("\n")
                run.output_bytes += len(line_bytes)
                if self._check_output_cap(run):
                    return
                self._enqueue(
                    run,
                    ForgeEvent(event="forge.stdout", run_id=run.run_id, line=line),
                )
        except asyncio.CancelledError:
            pass
        except Exception as exc:
            logger.exception(
                "unexpected error draining forge stdout for run %s: %s",
                run.run_id,
                exc,
            )
        finally:
            if run.proc is not None:
                try:
                    rc = await run.proc.wait()
                except Exception:
                    rc = -1

                elapsed_ms = int((time.monotonic() - run.started_at) * 1000)
                logger.info(
                    "forge run %s exited rc=%d duration_ms=%d",
                    run.run_id,
                    rc,
                    elapsed_ms,
                )

                if not run.terminal_emitted:
                    run.terminal_emitted = True
                    if rc == 0:
                        self._enqueue(
                            run,
                            ForgeEvent(
                                event="forge.completed",
                                run_id=run.run_id,
                                exit_code=rc,
                                duration_ms=elapsed_ms,
                            ),
                        )
                    else:
                        self._enqueue(
                            run,
                            ForgeEvent(
                                event="forge.failed",
                                run_id=run.run_id,
                                exit_code=rc,
                                duration_ms=elapsed_ms,
                                reason=f"process exited rc={rc}",
                            ),
                        )

            run.done.set()

    async def _drain_stderr(self, run: ForgeRun) -> None:
        """Read stderr from forge.sh, enqueue forge.stderr events, and tally bytes.

        Zen M1: stderr now respects FORGE_OUTPUT_CAP_BYTES too.  Previously a
        chatty stderr could blow past the cap with no enforcement at all.
        """
        assert run.proc is not None and run.proc.stderr is not None
        try:
            async for line_bytes in run.proc.stderr:
                line = line_bytes.decode("utf-8", errors="replace").rstrip("\n")
                run.output_bytes += len(line_bytes)
                if self._check_output_cap(run):
                    return
                self._enqueue(
                    run,
                    ForgeEvent(event="forge.stderr", run_id=run.run_id, line=line),
                )
        except asyncio.CancelledError:
            pass
        except Exception as exc:
            logger.debug("forge stderr drain error for run %s: %s", run.run_id, exc)

    async def _watchdog(self, run: ForgeRun) -> None:
        """Terminate the forge subprocess if it exceeds MAX_FORGE_SECONDS."""
        try:
            await asyncio.wait_for(run.done.wait(), timeout=MAX_FORGE_SECONDS)
        except asyncio.TimeoutError:
            logger.warning(
                "forge run %s exceeded MAX_FORGE_SECONDS=%d, terminating",
                run.run_id,
                MAX_FORGE_SECONDS,
            )
            if run.proc is not None:
                try:
                    run.proc.terminate()
                except ProcessLookupError:
                    pass
            if not run.terminal_emitted:
                run.terminal_emitted = True
                self._enqueue(
                    run,
                    ForgeEvent(
                        event="forge.failed",
                        run_id=run.run_id,
                        reason=f"timeout after {MAX_FORGE_SECONDS}s",
                    ),
                )
            run.done.set()
        except asyncio.CancelledError:
            pass

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _enqueue(self, run: ForgeRun, ev: ForgeEvent) -> None:
        """Put a ForgeEvent on the run queue.

        Terminal events (forge.completed, forge.failed) are never dropped — if
        the queue is full, stale non-terminal events are evicted to make room.
        Non-terminal events are dropped with a WARNING when the queue is full.
        """
        if ev.event in _TERMINAL_FORGE_EVENTS:
            while run.queue.full():
                try:
                    stale = run.queue.get_nowait()
                    logger.warning(
                        "forge run %s queue full — evicting %s to make room for terminal %s",
                        run.run_id,
                        stale.event,
                        ev.event,
                    )
                except asyncio.QueueEmpty:
                    break
            run.queue.put_nowait(ev)
            return

        try:
            run.queue.put_nowait(ev)
        except asyncio.QueueFull:
            logger.warning(
                "forge run %s queue full, dropping event %s",
                run.run_id,
                ev.event,
            )
