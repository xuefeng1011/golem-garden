"""API router: POST /v1/projects/{project_id}/forge and GET /v1/forge-runs/{run_id}/events."""

from __future__ import annotations

import asyncio
import logging
from pathlib import Path
from typing import Any, AsyncIterator

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field
from sse_starlette.sse import EventSourceResponse

from golem_gateway.config import ALLOWED_FORGE_COMMANDS
from golem_gateway.forge_runner import ForgeEvent, ForgeRun, ForgeRunner
from golem_gateway.registry import ProjectRegistry

logger = logging.getLogger(__name__)

router = APIRouter(tags=["forge"])


# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

def get_forge_runner(request: Request) -> ForgeRunner:
    return request.app.state.forge_runner  # type: ignore[no-any-return]


def get_registry(request: Request) -> ProjectRegistry:
    return request.app.state.registry  # type: ignore[no-any-return]


# ---------------------------------------------------------------------------
# Request / response models
# ---------------------------------------------------------------------------

class ForgeRequest(BaseModel):
    command: str
    args: list[str] = Field(default_factory=list)


class ForgeStartResponse(BaseModel):
    run_id: str


# ---------------------------------------------------------------------------
# POST /v1/projects/{project_id}/forge
# ---------------------------------------------------------------------------

@router.post("/v1/projects/{project_id}/forge", response_model=ForgeStartResponse)
async def start_forge(
    project_id: str,
    body: ForgeRequest,
    request: Request,
) -> ForgeStartResponse:
    """Spawn a forge.sh subcommand and return the run_id for SSE streaming."""
    registry: ProjectRegistry = get_registry(request)
    runner: ForgeRunner = get_forge_runner(request)

    # 404: unknown project
    project = await registry.get(project_id)
    if project is None:
        raise HTTPException(status_code=404, detail=f"project {project_id!r} not found")

    # 400: command not whitelisted
    if body.command not in ALLOWED_FORGE_COMMANDS:
        raise HTTPException(
            status_code=400,
            detail=(
                f"forge command {body.command!r} is not allowed. "
                f"Allowed commands: {sorted(ALLOWED_FORGE_COMMANDS)}"
            ),
        )

    project_path = Path(project.path)

    try:
        run = await runner.spawn(
            command=body.command,
            args=body.args,
            project_id=project_id,
            project_path=project_path,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except RuntimeError as exc:
        logger.error("failed to spawn forge run: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    return ForgeStartResponse(run_id=run.run_id)


# ---------------------------------------------------------------------------
# GET /v1/forge-runs/{run_id}/events  (SSE)
# ---------------------------------------------------------------------------

@router.delete("/v1/forge-runs/{run_id}", status_code=204)
async def cancel_forge_run(
    run_id: str,
    request: Request,
) -> None:
    """Explicitly terminate a running forge subprocess (and its native tree).

    Lets the UI stop button reliably kill the backend run instead of relying
    solely on SSE disconnect detection. 404 if the run is unknown/already gone.
    """
    runner: ForgeRunner = get_forge_runner(request)
    run = await runner.get_run(run_id)
    if run is None:
        raise HTTPException(status_code=404, detail=f"forge run {run_id!r} not found")
    await runner.terminate_run(run_id)


@router.get("/v1/forge-runs/{run_id}/events")
async def forge_events(
    run_id: str,
    request: Request,
) -> EventSourceResponse:
    """Stream ForgeEvents for the given run as Server-Sent Events.

    Returns 404 immediately (before opening the SSE stream) if run_id is
    unknown.  Returns 409 if another client is already subscribed.  The stream
    ends after emitting forge.completed or forge.failed.  Heartbeats are sent
    every 15 s to keep proxies alive.

    On client disconnect the forge subprocess is terminated and the run evicted.
    """
    runner: ForgeRunner = get_forge_runner(request)

    run = await runner.get_run(run_id)
    if run is None:
        raise HTTPException(status_code=404, detail=f"forge run {run_id!r} not found")
    if run.subscribed:
        raise HTTPException(
            status_code=409,
            detail=f"forge run {run_id!r} already has an active subscriber",
        )
    run.subscribed = True

    return EventSourceResponse(_forge_event_generator(run, runner))


async def _forge_event_generator(
    run: ForgeRun,
    runner: ForgeRunner,
) -> AsyncIterator[dict[str, Any]]:
    """Yield SSE dicts until the forge run completes, fails, or client disconnects.

    The finally block runs on both normal termination and client disconnect
    (CancelledError / GeneratorExit from sse-starlette), ensuring the subprocess
    is always cleaned up.
    """
    try:
        while True:
            try:
                ev: ForgeEvent = await asyncio.wait_for(run.queue.get(), timeout=15.0)
            except asyncio.TimeoutError:
                yield {"event": "heartbeat", "data": "{}"}
                continue

            yield {"event": ev.event, "data": ev.model_dump_json()}

            if ev.event in ("forge.completed", "forge.failed"):
                break
    finally:
        await runner.terminate_run(run.run_id)
