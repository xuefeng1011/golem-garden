"""FastAPI application entry point."""

from __future__ import annotations

from contextlib import asynccontextmanager
from typing import AsyncIterator

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from golem_gateway.api_activity import router as activity_router
from golem_gateway.api_artifacts import router as artifacts_router
from golem_gateway.api_console import router as console_router
from golem_gateway.api_forge import router as forge_router
from golem_gateway.api_flows import router as flows_router
from golem_gateway.api_missions import router as missions_router
from golem_gateway.api_projects import router as projects_router
from golem_gateway.api_runs import router as runs_router
from golem_gateway.api_sessions import router as sessions_router
from golem_gateway.api_skills import global_router as global_skills_router
from golem_gateway.api_skills import router as skills_router
from golem_gateway.api_souls import router as souls_router
from golem_gateway.api_studios import router as studios_router
from golem_gateway.api_traces import router as traces_router
from golem_gateway.config import CORS_ORIGINS, HOST, PORT
from golem_gateway.forge_runner import ForgeRunner
from golem_gateway.registry import ProjectRegistry
from golem_gateway.session_manager import SessionManager


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Create the SessionManager, ForgeRunner, and ProjectRegistry at startup; shut down on exit."""
    registry = ProjectRegistry()
    await registry.load()
    app.state.registry = registry
    app.state.session_manager = SessionManager()
    app.state.forge_runner = ForgeRunner()
    try:
        yield
    finally:
        await app.state.session_manager.shutdown()
        await app.state.forge_runner.shutdown()


app = FastAPI(
    title="GolemGarden Gateway",
    version="0.4.0",
    description="Gateway for SOUL metadata and Claude Code subprocess bridge.",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS,
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["*"],
)

app.include_router(projects_router)
app.include_router(studios_router)
app.include_router(souls_router)
app.include_router(activity_router)
app.include_router(skills_router)
app.include_router(global_skills_router)
app.include_router(runs_router)
app.include_router(sessions_router)
app.include_router(forge_router)
app.include_router(traces_router)
app.include_router(missions_router)
app.include_router(flows_router)
app.include_router(artifacts_router)
app.include_router(console_router)


@app.get("/health", tags=["system"])
def health() -> dict[str, str]:
    return {"status": "ok"}


def cli() -> None:
    """Console-script entry point for `golem-gateway`."""
    import uvicorn

    uvicorn.run(
        "golem_gateway.main:app",
        host=HOST,
        port=PORT,
        reload=False,
    )


if __name__ == "__main__":
    cli()
