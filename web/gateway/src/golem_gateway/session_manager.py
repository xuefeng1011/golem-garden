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
import re
import signal
import time
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Callable

from golem_gateway.config import (
    CLAUDE_ARGS_BASE,
    CLAUDE_CMD,
    INPUT_MAX_BYTES,
    MAX_RUN_SECONDS,
    RUN_QUEUE_MAXSIZE,
    RUN_RAW_CAP_BYTES,
)
from golem_gateway.events import (
    HermesEvent,
    MessageDeltaEvent,
    RunCompletedEvent,
    RunContext,
    RunFailedEvent,
    SessionInitEvent,
    ToolStartedEvent,
    parse_stream_event,
)
from golem_gateway.sessions_db import get_session_store
from golem_gateway.souls import SoulDetail

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------

@dataclass
class Run:
    run_id: str
    session_id: str
    soul_id: str
    project_id: str
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
    # Accumulated assistant text across all message.delta events.
    assistant_text: str = ""
    # Zen F4: tracked separately so we don't re-encode assistant_text on every
    # delta to measure its byte length.
    assistant_text_bytes: int = 0
    # Set once the cap is hit so the truncation marker is appended at most once.
    assistant_text_truncated: bool = False
    # Tool usage log: brief entries accumulated during the run.
    tool_log: list[str] = field(default_factory=list)
    # Called once with the accumulated assistant text after run.completed is enqueued.
    on_terminal: Callable[[str], None] | None = None
    # Accumulated stderr lines for post-exit inspection (truncated at ~4 KiB total).
    stderr_buffer: list[str] = field(default_factory=list)
    # Terminal event outcome: "success" | "fail" | "" (unknown/not-yet-set).
    terminal_result: str = ""
    # Usage dict from RunCompletedEvent (tokens etc.); empty dict if unavailable.
    terminal_usage: dict = field(default_factory=dict)
    # Duration in milliseconds from RunCompletedEvent; 0 if unavailable.
    terminal_duration_ms: int = 0
    # Model string from SessionInitEvent (populated on first session.init).
    session_model: str = ""
    # Raw stdout lines buffered in memory for trajectory persistence (G1).
    raw_lines: list[str] = field(default_factory=list)
    raw_bytes: int = 0
    raw_truncated: bool = False
    # ISO-8601 UTC timestamp recorded at spawn time.
    ts_start_iso: str = ""
    # Resolved project filesystem path — set by spawn_run for persist_run.
    project_path: "Path | None" = None


# Terminal event type names — these must never be dropped from the queue.
_TERMINAL_EVENTS: frozenset[str] = frozenset({"run.completed", "run.failed"})

# Zen F4: cap accumulated assistant text per run.  A pathological / runaway
# assistant could otherwise grow assistant_text without bound and OOM the
# process or push a multi-megabyte payload into sqlite at persist time.
ASSISTANT_TEXT_CAP_BYTES: int = 256 * 1024


# ---------------------------------------------------------------------------
# System prompt builder
# ---------------------------------------------------------------------------

def _build_system_prompt(
    *,
    soul_name: str,
    soul_rank: str,
    soul_specialty: list[str],
    soul_body: str,
    history: list[dict],
) -> str:
    """Wrap the SOUL body with an identity header.

    Phase 8: ``history`` arg is kept for API compatibility but is no longer
    embedded in the system prompt. Claude maintains conversation context
    natively via ``--session-id`` / ``--resume`` (see ``spawn_run``), which
    preserves prompt cache hits across turns.
    """
    specialty_str = ", ".join(soul_specialty) if soul_specialty else "—"
    header = (
        f"# SOUL Identity\n"
        f"You are **{soul_name}** ({soul_rank}). "
        f"Specialty: {specialty_str}.\n"
        f"Respond as {soul_name}, staying in your area of expertise. "
        f"Keep your voice consistent across turns.\n\n"
    )
    return header + soul_body.strip() + "\n"


# ---------------------------------------------------------------------------
# SessionManager
# ---------------------------------------------------------------------------

class SessionManager:
    # F2 (Phase 8.1 hardening): regex with word boundaries to anchor the
    # session-lost match. Substring matching previously could trigger on
    # incidental phrases like "tool session not found in cache".
    _SESSION_LOST_PATTERN: "re.Pattern[str]" = re.compile(
        r"\b(session (file )?not found|could not resume session|no such session)\b",
        re.IGNORECASE,
    )
    # Max bytes to accumulate in stderr_buffer before discarding new lines.
    _STDERR_BUFFER_MAX_BYTES: int = 4 * 1024  # 4 KiB

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
        soul_detail: "SoulDetail",
        history: list[dict],
        project_path: "Path",
        project_id: str,
        prior_turn_count: int | None = None,
        model: str | None = None,
    ) -> Run:
        """Create a Run, spawn the subprocess, and begin draining stdout.

        Raises RuntimeError if CLAUDE_CMD is not found or the process fails
        to start.
        """
        from pathlib import Path  # local import to avoid circular at module level

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
            project_id=project_id,
            proc=None,
            queue=asyncio.Queue(maxsize=RUN_QUEUE_MAXSIZE),
            done=asyncio.Event(),
            started_at=time.monotonic(),
            ts_start_iso=datetime.now(timezone.utc).isoformat(),
            project_path=project_path,
        )

        # Build enhanced system prompt: identity header + SOUL body + history.
        system_prompt = _build_system_prompt(
            soul_name=soul_detail.name,
            soul_rank=soul_detail.rank,
            soul_specialty=soul_detail.specialty,
            soul_body=soul_detail.content,
            history=history,
        )
        prompt_bytes = len(system_prompt.encode("utf-8"))

        # Phase 8: decide between --session-id (first turn, claude creates the
        # session keyed by our UUID) and --resume (continuing turn, claude
        # loads its existing session file). Mutually exclusive.
        # If a session row exists in the DB but message_count is 0 (e.g. crash
        # mid-turn before persistence), --session-id is still safe — claude
        # will overwrite with an empty session.
        # Phase 8: prior_turn_count is captured by api_runs BEFORE it adds the
        # caller's user message to the DB, so it correctly reflects whether
        # this is the first turn of the session. We accept it as a param to
        # avoid the race where reading message_count here always returns ≥1
        # because the user message has already been persisted upstream.
        if prior_turn_count is not None:
            prior_count = prior_turn_count
        else:
            # Defensive fallback for any caller that forgot to pass it.
            store = get_session_store(project_path)
            try:
                prior_count = store.get_message_count(sid)
            except Exception as exc:
                logger.warning(
                    "get_message_count failed for session %s (%s); defaulting to 0",
                    sid, exc,
                )
                prior_count = 0

        if prior_count == 0:
            session_args = ["--session-id", sid]
        else:
            session_args = ["--resume", sid]

        # Build argument list — never interpolated into a shell string.
        # config.py guarantees CLAUDE_CMD is a real .exe (or None, caught above).
        # The "--" separator prevents input_text starting with "-" from being
        # mis-parsed as a flag by claude's argument parser.
        args: list[str] = [
            CLAUDE_CMD,
            *CLAUDE_ARGS_BASE,
            *session_args,
            # Per-run model override (C4) — RunRequest 가 화이트리스트 검증함
            *(["--model", model] if model else []),
            "--append-system-prompt",
            system_prompt,
            "--",
            input_text,
        ]

        logger.info(
            "spawning run %s (session=%s soul=%s project=%s system_prompt_bytes=%d history_turns=%d session_mode=%s prior_count=%d)",
            run_id, sid, soul_id, project_id, prompt_bytes, len(history),
            session_args[0], prior_count,
        )
        logger.debug("claude exec: %r + %d extra args", args[0], len(args) - 1)

        try:
            # Zen F5: claude subprocess INTENTIONALLY inherits the full parent
            # env. It needs ANTHROPIC_API_KEY (or AWS/GCP credentials for
            # Bedrock/Vertex), CLAUDE_CODE_* settings, NPM/Node config, and
            # whatever the operator has configured for their auth setup. This
            # is the opposite of forge_runner.py, which builds a minimal env
            # because forge.sh does not need any of those credentials.
            proc = await asyncio.create_subprocess_exec(
                *args,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                stdin=asyncio.subprocess.DEVNULL,
                cwd=str(project_path),
                env={**os.environ},
                start_new_session=True,
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

    def active_runs_for(self, project_id: str) -> list[Run]:
        """Return all active (not-done) runs belonging to project_id.

        Intended for the console aggregation endpoint (G10).  Uses a snapshot
        of the internal dict so the caller never touches private state directly.
        """
        return [
            run
            for run in self._runs.values()
            if run.project_id == project_id and not run.done.is_set()
        ]

    async def terminate_run(self, run_id: str) -> None:
        """Kill subprocess, cancel tasks, evict from _runs. Idempotent."""
        async with self._lock:
            run = self._runs.pop(run_id, None)
        if run is None:
            return

        # Terminate subprocess tree — plain proc.terminate() only signals the
        # direct child, leaving claude grandchildren as orphans on all platforms.
        if run.proc is not None and run.proc.returncode is None:
            proc = run.proc
            pid = proc.pid
            if os.name == "nt" and pid:
                try:
                    tk = await asyncio.create_subprocess_exec(
                        "taskkill", "/F", "/T", "/PID", str(pid),
                        stdout=asyncio.subprocess.DEVNULL,
                        stderr=asyncio.subprocess.DEVNULL,
                    )
                    await asyncio.wait_for(tk.wait(), timeout=5.0)
                except (OSError, asyncio.TimeoutError):
                    pass
            elif os.name != "nt" and pid and hasattr(os, "getpgid"):
                try:
                    pgid = os.getpgid(pid)
                    os.killpg(pgid, signal.SIGTERM)
                    try:
                        await asyncio.wait_for(proc.wait(), timeout=2.0)
                    except asyncio.TimeoutError:
                        os.killpg(pgid, signal.SIGKILL)
                        await proc.wait()
                except (ProcessLookupError, PermissionError, OSError):
                    pass  # fall through to plain terminate/kill
            # graceful + force fallback (if taskkill/killpg missed or failed)
            if proc.returncode is None:
                try:
                    proc.terminate()
                    try:
                        await asyncio.wait_for(proc.wait(), timeout=2.0)
                    except asyncio.TimeoutError:
                        proc.kill()
                        await proc.wait()
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

    async def terminate_runs_for_project(self, project_id: str) -> int:
        """Terminate all active runs belonging to the given project_id.

        Returns the count of runs terminated.
        """
        async with self._lock:
            run_ids = [
                rid for rid, run in self._runs.items()
                if run.project_id == project_id
            ]
        if not run_ids:
            return 0
        await asyncio.gather(
            *(self.terminate_run(rid) for rid in run_ids),
            return_exceptions=True,
        )
        return len(run_ids)

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

                # G1: buffer raw line in memory only (no disk I/O during run).
                if not run.raw_truncated:
                    line_len = len(line.encode("utf-8"))
                    if run.raw_bytes + line_len <= RUN_RAW_CAP_BYTES:
                        run.raw_lines.append(line)
                        run.raw_bytes += line_len
                    else:
                        run.raw_truncated = True

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
                    # Accumulate assistant text for persistence (Zen F4: capped).
                    if ev.event == "message.delta":
                        if isinstance(ev, MessageDeltaEvent):
                            self._accumulate_assistant_text(run, ev.text)
                    # Accumulate tool usage for persistence.
                    elif ev.event == "tool.started":
                        if isinstance(ev, ToolStartedEvent):
                            run.tool_log.append(ev.tool_name)
                    # Capture terminal outcome + usage for growth-log.
                    elif ev.event == "run.completed":
                        if isinstance(ev, RunCompletedEvent):
                            run.terminal_result = "fail" if ev.is_error else "success"
                            run.terminal_usage = ev.usage or {}
                            run.terminal_duration_ms = ev.duration_ms
                    elif ev.event == "run.failed":
                        run.terminal_result = "fail"
                    # Capture model from session.init.
                    elif ev.event == "session.init":
                        if isinstance(ev, SessionInitEvent):
                            run.session_model = ev.model
                    self._enqueue(run, ev)
        except asyncio.CancelledError:
            pass
        except Exception as exc:
            logger.exception("unexpected error draining stdout for run %s: %s", run.run_id, exc)
        finally:
            # Wait for process to fully exit.
            #
            # Cancellation-safety (Phase A 라이브 발견): SSE 제너레이터가 정상
            # 종료/disconnect 시 terminate_run 으로 이 drain task 를 cancel 한다.
            # 그때 이 finally 안의 await 에서 CancelledError 가 재발생해
            # 아래의 모든 터미널 부기(on_terminal→growth-log, persist_run,
            # done.set)가 통째로 스킵되던 잠복 버그가 있었다 — 구독자가 있는
            # 모든 런에서 growth-log 가 누락된 원인. cancel 을 흡수하고
            # 부기를 끝까지 수행한다 (task 는 어차피 직후 종료).
            if run.proc is not None:
                try:
                    rc = await run.proc.wait()
                except asyncio.CancelledError:
                    rc = run.proc.returncode if run.proc.returncode is not None else -1
                except Exception:
                    rc = -1

                logger.info("run %s exited rc=%d", run.run_id, rc)

                # Phase 8.1 race fix: ensure all stderr is consumed before
                # pattern detection. proc.wait() returning does NOT guarantee
                # the concurrent _drain_stderr task has finished consuming the
                # pipe; for fast-exit cases (claude rejecting --resume) the
                # session-lost line could still be in the kernel buffer.
                # Shield prevents external cancellation from interrupting the
                # drain; 0.5s cap prevents stuck draining from blocking us.
                if run.stderr_task is not None and not run.stderr_task.done():
                    try:
                        await asyncio.wait_for(
                            asyncio.shield(run.stderr_task), timeout=0.5
                        )
                    except (asyncio.TimeoutError, asyncio.CancelledError):
                        pass  # best-effort

                if not run.terminal_emitted:
                    # Process crashed before emitting a result event.
                    # Guard with terminal_emitted so watchdog timeout can't double-emit.
                    run.terminal_emitted = True
                    # F2: detect "session lost" via anchored regex (substring
                    # matching previously over-fired on incidental phrases).
                    stderr_text = " ".join(run.stderr_buffer)
                    if self._SESSION_LOST_PATTERN.search(stderr_text):
                        reason = (
                            "claude session file missing or GC'd — "
                            "DELETE this session and start fresh "
                            "(claude session lost — please retry: "
                            "DELETE /v1/projects/{project_id}/sessions/{session_id})"
                        )
                        logger.warning(
                            "run %s: detected lost session (rc=%d); emitting clear error",
                            run.run_id, rc,
                        )
                    else:
                        reason = f"process exited rc={rc}"
                    self._enqueue(
                        run,
                        RunFailedEvent(
                            run_id=run.run_id,
                            session_id=run.session_id,
                            reason=reason,
                        ),
                    )

            # Fire persistence callback with accumulated assistant text.
            if run.on_terminal is not None:
                try:
                    run.on_terminal(run.assistant_text)
                except Exception as cb_exc:
                    logger.warning(
                        "on_terminal callback error for run %s: %s", run.run_id, cb_exc
                    )

            # Persist run trajectory (Phase A — G1: single flush at terminal).
            if run.project_path is not None:
                try:
                    import golem_gateway.runs_store as _rs
                    _rs.persist_run(
                        run.project_path,
                        run_id=run.run_id,
                        session_id=run.session_id,
                        soul_id=run.soul_id,
                        model=run.session_model,
                        result=run.terminal_result or "fail",
                        ts_start=run.ts_start_iso,
                        duration_ms=run.terminal_duration_ms,
                        usage=run.terminal_usage,
                        tool_log=run.tool_log,
                        raw_lines=run.raw_lines,
                        raw_truncated=run.raw_truncated,
                    )
                except Exception as persist_exc:
                    logger.warning(
                        "run trajectory persist error for %s: %s", run.run_id, persist_exc
                    )

            run.done.set()

    async def _drain_stderr(self, run: Run) -> None:
        """Read stderr from the subprocess, log it, and buffer it for inspection.

        Claude Code writes status/progress to stderr; non-empty stderr is
        normal and should not be treated as an error.

        F2: lines are accumulated into run.stderr_buffer (capped at 4 KiB
        total) so that _drain_stdout's finally block can inspect stderr for
        "session not found" patterns after the process exits.
        """
        assert run.proc is not None and run.proc.stderr is not None
        buffered_bytes = 0
        try:
            async for line_bytes in run.proc.stderr:
                line = line_bytes.decode("utf-8", errors="replace").rstrip()
                if line:
                    logger.info("claude stderr (run=%s): %s", run.run_id, line)
                    # Accumulate for post-exit inspection, bounded at 4 KiB.
                    line_len = len(line.encode("utf-8"))
                    if buffered_bytes + line_len <= self._STDERR_BUFFER_MAX_BYTES:
                        run.stderr_buffer.append(line)
                        buffered_bytes += line_len
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
                run.terminal_result = "timeout"
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

    def _accumulate_assistant_text(self, run: Run, text: str) -> None:
        """Append assistant delta text, enforcing ASSISTANT_TEXT_CAP_BYTES.

        Tracks byte-length in run.assistant_text_bytes to avoid re-encoding
        the full string on every delta.  Once the cap is hit, a one-shot
        truncation marker is appended and further deltas are dropped.
        """
        if run.assistant_text_truncated:
            return
        delta_bytes = len(text.encode("utf-8"))
        if run.assistant_text_bytes + delta_bytes <= ASSISTANT_TEXT_CAP_BYTES:
            run.assistant_text += text
            run.assistant_text_bytes += delta_bytes
            return
        # Cap exceeded — append a single truncation marker and stop.
        marker = "\n\n…[truncated at 256KB]…"
        run.assistant_text += marker
        run.assistant_text_bytes += len(marker.encode("utf-8"))
        run.assistant_text_truncated = True
        logger.warning(
            "run %s assistant_text capped at %d bytes (cap=%d)",
            run.run_id,
            run.assistant_text_bytes,
            ASSISTANT_TEXT_CAP_BYTES,
        )

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
