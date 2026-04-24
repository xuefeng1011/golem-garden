"""Session and Run lifecycle management.

SessionManager owns subprocess spawning, the per-run asyncio.Queue of
HermesEvents, and orderly shutdown.  It is created once at app lifespan
start and stored in app.state.session_manager.

Notes on session_id semantics (MVP):
  session_id is a client-controlled tab identity.  Multiple runs CAN share
  one session_id (e.g. a conversation in the same browser tab), but in this
  MVP each run always spawns a brand-new subprocess — there is no Claude
  --resume session reuse.  Phase 4 will wire up --resume once the session
  persistence story is clearer.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import time
import uuid
from dataclasses import dataclass, field

from golem_gateway.config import (
    CLAUDE_ARGS_BASE,
    CLAUDE_CMD,
    INPUT_MAX_BYTES,
    MAX_RUN_SECONDS,
    RUN_QUEUE_MAXSIZE,
    SUBPROCESS_CWD,
)
from golem_gateway.events import (
    HermesEvent,
    RunCompletedEvent,
    RunContext,
    RunFailedEvent,
    parse_stream_event,
)

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------

@dataclass
class Run:
    run_id: str
    session_id: str
    soul_id: str
    proc: asyncio.subprocess.Process | None
    queue: asyncio.Queue[HermesEvent]
    done: asyncio.Event
    started_at: float
    # Background tasks stored for cancellation on teardown.
    drain_task: asyncio.Task[None] | None = None
    stderr_task: asyncio.Task[None] | None = None
    watchdog_task: asyncio.Task[None] | None = None
    # Prevents double-emit of terminal events from drain + watchdog racing.
    terminal_emitted: bool = False
    # Prevents a second SSE subscriber from splitting queue events.
    subscribed: bool = False
    # Legacy catch-all task list (kept for compatibility; prefer named fields).
    _tasks: list[asyncio.Task[None]] = field(default_factory=list)


# Terminal event type names — these must never be dropped from the queue.
_TERMINAL_EVENTS: frozenset[str] = frozenset({"run.completed", "run.failed"})


# ---------------------------------------------------------------------------
# SessionManager
# ---------------------------------------------------------------------------

class SessionManager:
    def __init__(self) -> None:
        self._runs: dict[str, Run] = {}
        # session_id -> set of run_ids (for future GC / history)
        self._sessions: dict[str, set[str]] = {}
        self._lock = asyncio.Lock()

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    async def spawn_run(
        self,
        *,
        input_text: str,
        session_id: str | None,
        soul_id: str,
        soul_content: str,
    ) -> Run:
        """Create a Run, spawn the subprocess, and begin draining stdout.

        Raises RuntimeError if CLAUDE_CMD is not found or the process fails
        to start.
        """
        if CLAUDE_CMD is None:
            raise RuntimeError(
                "claude executable not found on PATH.  "
                "Install Claude Code CLI and ensure it is on PATH."
            )

        if len(input_text.encode("utf-8")) > INPUT_MAX_BYTES:
            raise ValueError(f"input exceeds {INPUT_MAX_BYTES} bytes")

        run_id = str(uuid.uuid4())
        sid = session_id or str(uuid.uuid4())

        run = Run(
            run_id=run_id,
            session_id=sid,
            soul_id=soul_id,
            proc=None,
            queue=asyncio.Queue(maxsize=RUN_QUEUE_MAXSIZE),
            done=asyncio.Event(),
            started_at=time.monotonic(),
        )

        # Build argument list — never interpolated into a shell string.
        # config.py guarantees CLAUDE_CMD is a real .exe (or None, caught above).
        # The "--" separator prevents input_text starting with "-" from being
        # mis-parsed as a flag by claude's argument parser.
        args: list[str] = [
            CLAUDE_CMD,
            *CLAUDE_ARGS_BASE,
            "--append-system-prompt",
            soul_content,
            "--",
            input_text,
        ]

        logger.info("spawning run %s (session=%s soul=%s)", run_id, sid, soul_id)
        logger.debug("claude exec: %r + %d extra args", args[0], len(args) - 1)

        try:
            proc = await asyncio.create_subprocess_exec(
                *args,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                stdin=asyncio.subprocess.DEVNULL,
                cwd=str(SUBPROCESS_CWD),
                env={**os.environ},
            )
        except (OSError, FileNotFoundError) as exc:
            raise RuntimeError(f"failed to spawn claude subprocess: {exc}") from exc

        run.proc = proc

        async with self._lock:
            self._runs[run_id] = run
            self._sessions.setdefault(sid, set()).add(run_id)

        # Start background tasks and store references for teardown.
        run.drain_task = asyncio.create_task(
            self._drain_stdout(run), name=f"drain-{run_id}"
        )
        run.stderr_task = asyncio.create_task(
            self._drain_stderr(run), name=f"stderr-{run_id}"
        )
        run.watchdog_task = asyncio.create_task(
            self._watchdog(run), name=f"watchdog-{run_id}"
        )
        run._tasks.extend([run.drain_task, run.stderr_task, run.watchdog_task])

        return run

    async def get_run(self, run_id: str) -> Run | None:
        return self._runs.get(run_id)

    async def terminate_run(self, run_id: str) -> None:
        """Kill subprocess, cancel tasks, evict from _runs. Idempotent."""
        async with self._lock:
            run = self._runs.pop(run_id, None)
        if run is None:
            return

        # Terminate subprocess.
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

        # Cancel background tasks.
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
        """Terminate all live runs on app shutdown. Reuses terminate_run for clean teardown."""
        logger.info("SessionManager shutting down (%d runs)", len(self._runs))
        async with self._lock:
            run_ids = list(self._runs.keys())
        await asyncio.gather(
            *(self.terminate_run(rid) for rid in run_ids),
            return_exceptions=True,
        )

    # ------------------------------------------------------------------
    # Internal tasks
    # ------------------------------------------------------------------

    async def _drain_stdout(self, run: Run) -> None:
        """Read stream-json lines from stdout, parse, and enqueue events."""
        assert run.proc is not None and run.proc.stdout is not None

        ctx = RunContext(run_id=run.run_id, session_id=run.session_id)

        try:
            async for line_bytes in run.proc.stdout:
                line = line_bytes.decode("utf-8", errors="replace").rstrip()
                if not line:
                    continue
                try:
                    raw = json.loads(line)
                except json.JSONDecodeError:
                    logger.warning(
                        "non-json line from claude (run=%s): %r",
                        run.run_id,
                        line[:200],
                    )
                    continue

                events = parse_stream_event(raw, context=ctx)
                for ev in events:
                    if ev.event in _TERMINAL_EVENTS:
                        run.terminal_emitted = True
                    self._enqueue(run, ev)
        except asyncio.CancelledError:
            pass
        except Exception as exc:
            logger.exception("unexpected error draining stdout for run %s: %s", run.run_id, exc)
        finally:
            # Wait for process to fully exit
            if run.proc is not None:
                try:
                    rc = await run.proc.wait()
                except Exception:
                    rc = -1

                logger.info("run %s exited rc=%d", run.run_id, rc)

                if not run.terminal_emitted:
                    # Process crashed before emitting a result event.
                    # Guard with terminal_emitted so watchdog timeout can't double-emit.
                    run.terminal_emitted = True
                    self._enqueue(
                        run,
                        RunFailedEvent(
                            run_id=run.run_id,
                            session_id=run.session_id,
                            reason=f"process exited rc={rc}",
                        ),
                    )

            run.done.set()

    async def _drain_stderr(self, run: Run) -> None:
        """Read stderr from the subprocess and log at INFO.

        Claude Code writes status/progress to stderr; non-empty stderr is
        normal and should not be treated as an error.
        """
        assert run.proc is not None and run.proc.stderr is not None
        try:
            async for line_bytes in run.proc.stderr:
                line = line_bytes.decode("utf-8", errors="replace").rstrip()
                if line:
                    logger.info("claude stderr (run=%s): %s", run.run_id, line)
        except asyncio.CancelledError:
            pass
        except Exception as exc:
            logger.debug("stderr drain error for run %s: %s", run.run_id, exc)

    async def _watchdog(self, run: Run) -> None:
        """Terminate the subprocess if it exceeds MAX_RUN_SECONDS."""
        try:
            await asyncio.wait_for(run.done.wait(), timeout=MAX_RUN_SECONDS)
        except asyncio.TimeoutError:
            logger.warning(
                "run %s exceeded MAX_RUN_SECONDS=%d, terminating",
                run.run_id,
                MAX_RUN_SECONDS,
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
                    RunFailedEvent(
                        run_id=run.run_id,
                        session_id=run.session_id,
                        reason=f"timeout after {MAX_RUN_SECONDS}s",
                    ),
                )
            run.done.set()
        except asyncio.CancelledError:
            pass

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _enqueue(self, run: Run, ev: HermesEvent) -> None:
        """Put an event on the run queue.

        Terminal events (run.completed, run.failed) are never dropped — if the
        queue is full, stale non-terminal events are evicted to make room.
        Non-terminal events are dropped with a WARNING when the queue is full.
        """
        if ev.event in _TERMINAL_EVENTS:
            # Evict oldest non-terminal events until there is space.
            while run.queue.full():
                try:
                    stale = run.queue.get_nowait()
                    logger.warning(
                        "run %s queue full — evicting %s to make room for terminal event %s",
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
                "run %s queue full (maxsize=%d), dropping event %s",
                run.run_id,
                RUN_QUEUE_MAXSIZE,
                ev.event,
            )
