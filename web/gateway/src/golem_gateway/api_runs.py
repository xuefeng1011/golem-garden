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

from golem_gateway import souls
from golem_gateway.config import INPUT_MAX_BYTES
from golem_gateway.events import HermesEvent
from golem_gateway.registry import ProjectRegistry
from golem_gateway.session_manager import Run, SessionManager

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

    # Assign session_id here so response always carries it.
    session_id = body.session_id or str(uuid.uuid4())

    try:
        run = await manager.spawn_run(
            input_text=body.input,
            session_id=session_id,
            soul_id=body.soul_id,
            soul_detail=soul,
            history=[t.model_dump() for t in body.history],
            project_path=project_path,
            project_id=project_id,
        )
    except RuntimeError as exc:
        logger.error("failed to spawn run: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc)) from exc

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
