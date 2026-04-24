"""API router: POST /v1/runs and GET /v1/runs/{run_id}/events."""

from __future__ import annotations

import asyncio
import logging
import uuid
from typing import Any, AsyncIterator

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, field_validator
from sse_starlette.sse import EventSourceResponse

from golem_gateway import souls
from golem_gateway.config import INPUT_MAX_BYTES
from golem_gateway.events import HermesEvent
from golem_gateway.session_manager import Run, SessionManager

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1", tags=["runs"])


# ---------------------------------------------------------------------------
# Dependency
# ---------------------------------------------------------------------------

def get_manager(request: Request) -> SessionManager:
    """Retrieve the singleton SessionManager stored in app.state."""
    return request.app.state.session_manager  # type: ignore[no-any-return]


# ---------------------------------------------------------------------------
# Request / response models
# ---------------------------------------------------------------------------

class RunRequest(BaseModel):
    input: str
    session_id: str | None = None
    soul_id: str

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
# POST /v1/runs
# ---------------------------------------------------------------------------

@router.post("/runs", response_model=RunResponse)
async def create_run(
    body: RunRequest,
    manager: SessionManager = Depends(get_manager),
) -> RunResponse:
    """Spawn a Claude Code subprocess for the given input + SOUL and return run_id."""

    # 413: oversized input
    if len(body.input.encode("utf-8")) > INPUT_MAX_BYTES:
        raise HTTPException(status_code=413, detail="input exceeds 32 KiB limit")

    # 404: unknown soul
    soul = souls.get_soul_by_id(body.soul_id)
    if soul is None:
        raise HTTPException(status_code=404, detail=f"soul {body.soul_id!r} not found")

    soul_content = soul.content

    # Assign session_id here so response always carries it.
    session_id = body.session_id or str(uuid.uuid4())

    try:
        run = await manager.spawn_run(
            input_text=body.input,
            session_id=session_id,
            soul_id=body.soul_id,
            soul_content=soul_content,
        )
    except RuntimeError as exc:
        logger.error("failed to spawn run: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    return RunResponse(run_id=run.run_id, session_id=run.session_id)


# ---------------------------------------------------------------------------
# GET /v1/runs/{run_id}/events  (SSE)
# ---------------------------------------------------------------------------

@router.get("/runs/{run_id}/events")
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
