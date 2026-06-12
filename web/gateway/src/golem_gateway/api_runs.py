"""API router: POST /v1/projects/{project_id}/runs and GET /v1/runs/{run_id}/events."""

from __future__ import annotations

import asyncio
import logging
import uuid
from pathlib import Path
from typing import Any, AsyncIterator, Literal

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field, field_validator
from sse_starlette.sse import EventSourceResponse

from golem_gateway import growth_log, souls
from golem_gateway.config import INPUT_MAX_BYTES
from golem_gateway.events import HermesEvent
from golem_gateway.registry import ProjectRegistry
from golem_gateway.session_manager import Run, SessionManager
from golem_gateway.sessions_db import get_session_store

logger = logging.getLogger(__name__)

router = APIRouter(tags=["runs"])


# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

def get_manager(request: Request) -> SessionManager:
    """Retrieve the singleton SessionManager stored in app.state."""
    return request.app.state.session_manager  # type: ignore[no-any-return]


def get_registry(request: Request) -> ProjectRegistry:
    return request.app.state.registry  # type: ignore[no-any-return]


# ---------------------------------------------------------------------------
# Request / response models
# ---------------------------------------------------------------------------

HISTORY_MAX_BYTES: int = 64 * 1024  # 64 KiB combined history cap


class HistoryTurn(BaseModel):
    role: Literal["user", "assistant"]
    content: str


class RunRequest(BaseModel):
    input: str
    session_id: str | None = None
    soul_id: str
    history: list[HistoryTurn] = Field(default_factory=list)
    # Per-run model override (C4). The client has always sent this field
    # (appStore.selectedModel) — the gateway previously ignored it.
    # Allowed: alias (opus/sonnet/haiku) or full claude-* model id,
    # mirroring lib/agent-runner.sh _map_model. None/"" → SOUL/CLI default.
    model: str | None = None

    @field_validator("model")
    @classmethod
    def validate_model(cls, v: str | None) -> str | None:
        if v is None or v == "":
            return None
        if v in {"opus", "sonnet", "haiku"} or v.startswith("claude-"):
            return v
        raise ValueError(
            "model must be one of opus/sonnet/haiku or a claude-* model id"
        )

    @field_validator("soul_id")
    @classmethod
    def validate_soul_id(cls, v: str) -> str:
        if not souls._VALID_SOUL_ID.match(v):
            raise ValueError(f"soul_id {v!r} contains invalid characters")
        return v

    @field_validator("input")
    @classmethod
    def validate_input_non_empty(cls, v: str) -> str:
        if not v or not v.strip():
            raise ValueError("input must be a non-empty string")
        return v


class RunResponse(BaseModel):
    run_id: str
    session_id: str


# ---------------------------------------------------------------------------
# POST /v1/projects/{project_id}/runs
# ---------------------------------------------------------------------------

@router.post("/v1/projects/{project_id}/runs", response_model=RunResponse)
async def create_run(
    project_id: str,
    body: RunRequest,
    manager: SessionManager = Depends(get_manager),
    registry: ProjectRegistry = Depends(get_registry),
) -> RunResponse:
    """Spawn a Claude Code subprocess for the given input + SOUL and return run_id."""

    # 404: unknown project
    project = await registry.get(project_id)
    if project is None:
        raise HTTPException(status_code=404, detail=f"project {project_id!r} not found")

    project_path = Path(project.path)

    # 413: oversized input
    if len(body.input.encode("utf-8")) > INPUT_MAX_BYTES:
        raise HTTPException(status_code=413, detail="input exceeds 32 KiB limit")

    # 413: oversized history
    history_bytes = sum(len(t.content.encode("utf-8")) for t in body.history)
    if history_bytes > HISTORY_MAX_BYTES:
        raise HTTPException(status_code=413, detail="history exceeds 64 KiB limit")

    # 404: unknown soul
    soul = souls.get_soul_by_id(project_path, body.soul_id)
    if soul is None:
        raise HTTPException(status_code=404, detail=f"soul {body.soul_id!r} not found")

    # Phase 8: session_id MUST be a valid UUID v4 because we pass it to claude
    # CLI as --session-id (which strictly requires UUID v4). If the caller did
    # not supply one, OR supplied something that does not parse as UUID v4,
    # generate a fresh server-side UUID and use that. The actual session_id
    # used is returned in the response so the client can track it.
    session_id = body.session_id or str(uuid.uuid4())
    try:
        parsed = uuid.UUID(session_id)
        if parsed.version != 4:
            raise ValueError(f"session_id is UUID v{parsed.version}, expected v4")
    except (ValueError, AttributeError, TypeError) as exc:
        logger.info(
            "client-supplied session_id %r invalid (%s); generating fresh UUID v4",
            session_id, exc,
        )
        session_id = str(uuid.uuid4())

    # Phase 8: body.history is now ignored — claude maintains conversation
    # context natively via --resume. We accept the field for backward compat
    # but log a hint when callers still send it so they can migrate.
    if body.history:
        logger.debug(
            "history field passed (%d turns) but ignored — using --resume for session %s",
            len(body.history), session_id,
        )

    # --- Session persistence: snapshot count + upsert session row BEFORE spawn ---
    store = get_session_store(project_path)
    # Phase 8: snapshot prior turn count first; spawn_run uses it to pick
    # --session-id (first turn) vs --resume (continuing). The user message is
    # NOT added yet — we wait until spawn_run succeeds to avoid leaving an
    # orphaned user row that would falsely bump prior_count on the retry,
    # forcing --resume against a never-created claude session (Zen Phase 8.1).
    prior_turn_count = store.get_user_assistant_count(session_id)
    store.upsert_session(session_id=session_id, soul_id=body.soul_id)

    try:
        run = await manager.spawn_run(
            input_text=body.input,
            session_id=session_id,
            soul_id=body.soul_id,
            soul_detail=soul,
            history=[t.model_dump() for t in body.history],
            project_path=project_path,
            project_id=project_id,
            prior_turn_count=prior_turn_count,
            model=body.model,
        )
    except Exception as exc:
        # Spawn failed before any user/assistant rows existed for this session.
        # Append a system marker so the UI can render the failure; the next
        # POST against the same session_id will see prior_turn_count=0 and
        # correctly retry with --session-id.
        logger.error("failed to spawn run for session %s: %s", session_id, exc)
        try:
            store.add_message(
                session_id=session_id,
                role="system",
                content=f"⚠ run failed to start: {exc}",
            )
        except Exception:
            logger.exception(
                "failed to record run-failure marker for session %s", session_id
            )
        # Surface 503 Service Unavailable for spawn failures (transient resource
        # condition) and 500 only for unexpected RuntimeError so callers can
        # tell them apart in their own retry logic.
        if isinstance(exc, RuntimeError):
            raise HTTPException(status_code=500, detail=str(exc)) from exc
        raise HTTPException(
            status_code=503, detail=f"failed to spawn claude: {exc}"
        ) from exc

    # Spawn succeeded — now safe to persist the user message. The on_terminal
    # callback (set below) will append the assistant reply once streaming completes.
    store.add_message(session_id=session_id, role="user", content=body.input)

    # Wire the on_terminal callback: persist assistant reply + tool summary
    # and append a growth-log entry for the chat run.
    soul_id_capture = body.soul_id
    input_capture = body.input

    def _persist_assistant(assistant_text: str) -> None:
        # Zen M2: batch the assistant message and the optional tool summary
        # into a single transaction (one open/close, one updated_at touch).
        msgs: list[dict] = []
        if assistant_text:
            msgs.append({
                "role": "assistant",
                "content": assistant_text,
                "soul_id": soul_id_capture,
            })
        if run.tool_log:
            msgs.append({
                "role": "tool",
                "content": "\n".join(run.tool_log),
                "soul_id": soul_id_capture,
            })
        if msgs:
            try:
                store.add_messages_batch(session_id=session_id, messages=msgs)
            except Exception:
                logger.exception(
                    "failed to persist assistant messages for run %s", run.run_id
                )

        # --- growth-log append (best-effort, never blocks chat response) ---
        # Determine result from terminal event captured by _drain_stdout.
        gl_result = run.terminal_result if run.terminal_result else "fail"

        # Extract token counts from usage dict (keys match claude stream-json).
        usage = run.terminal_usage or {}
        tokens_in: int = int(usage.get("input_tokens") or 0)
        tokens_out: int = int(usage.get("output_tokens") or 0)
        tokens_cache: int = int(usage.get("cache_read_input_tokens") or 0)

        # task: first 80 chars of user input, newlines stripped.
        task_summary = input_capture.replace("\n", " ").replace("\r", "").strip()[:80]

        growth_log.append_entry(
            project_path,
            soul_id_capture,
            task_summary,
            gl_result,
            model=run.session_model,
            tokens_in=tokens_in,
            tokens_out=tokens_out,
            tokens_cache=tokens_cache,
            duration_ms=run.terminal_duration_ms,
        )

    run.on_terminal = _persist_assistant

    return RunResponse(run_id=run.run_id, session_id=run.session_id)


# ---------------------------------------------------------------------------
# GET /v1/runs/{run_id}/events  (SSE — global, run_id is sufficient)
# ---------------------------------------------------------------------------

@router.get("/v1/runs/{run_id}/events")
async def run_events(
    run_id: str,
    manager: SessionManager = Depends(get_manager),
) -> EventSourceResponse:
    """Stream HermesEvents for the given run as Server-Sent Events.

    Returns 404 immediately (before opening the SSE stream) if run_id is
    unknown.  Returns 409 if another client is already subscribed (queue is
    single-consumer only).  The stream ends after emitting run.completed or
    run.failed.  Heartbeats are sent every 15 s to keep proxies alive.

    On client disconnect the subprocess is terminated and the Run is evicted.
    """
    run = await manager.get_run(run_id)
    if run is None:
        raise HTTPException(status_code=404, detail=f"run {run_id!r} not found")
    if run.subscribed:
        raise HTTPException(
            status_code=409,
            detail=f"run {run_id!r} already has an active subscriber",
        )
    run.subscribed = True

    return EventSourceResponse(_event_generator(run, manager))


async def _event_generator(
    run: Run, manager: SessionManager
) -> AsyncIterator[dict[str, Any]]:
    """Yield SSE dicts until the run completes, fails, or the client disconnects.

    The finally block runs on both normal termination and client disconnect
    (CancelledError / GeneratorExit from sse-starlette), ensuring the subprocess
    is always cleaned up.
    """
    try:
        while True:
            try:
                ev: HermesEvent = await asyncio.wait_for(run.queue.get(), timeout=15.0)
            except asyncio.TimeoutError:
                # Send a heartbeat so proxies don't drop the connection.
                yield {"event": "heartbeat", "data": "{}"}
                continue

            yield {"event": ev.event, "data": ev.model_dump_json()}

            if ev.event in ("run.completed", "run.failed"):
                break
    finally:
        # Cleanup on normal exit AND on client disconnect.
        # terminate_run is idempotent — safe to call even if already evicted.
        await manager.terminate_run(run.run_id)
