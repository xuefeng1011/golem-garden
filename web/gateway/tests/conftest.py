"""Shared pytest fixtures for golem-gateway tests."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
import pytest_asyncio
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from golem_gateway.main import app as _app
from golem_gateway.registry import ProjectRegistry


# ---------------------------------------------------------------------------
# tmp_project: minimal fake project directory
# ---------------------------------------------------------------------------


@pytest.fixture()
def tmp_project(tmp_path: Path) -> Path:
    """Create a minimal project directory with the soul/session markers."""
    golem_dir = tmp_path / ".golem"
    golem_dir.mkdir(parents=True)
    souls_dir = tmp_path / "souls"
    souls_dir.mkdir()
    # Minimal soul stubs so soul-related code can find something.
    (golem_dir / "souls").mkdir()
    _write_soul(golem_dir / "souls" / "nex.md", name="Nex", role="Director")
    _write_soul(souls_dir / "ryn.md", name="Ryn", role="Backend Developer")
    return tmp_path


def _write_soul(path: Path, *, name: str, role: str) -> None:
    path.write_text(
        f"---\nname: {name}\nrole: {role}\nrank: Novice\nspecialty: []\n---\n\n# {name}\n",
        encoding="utf-8",
    )


# ---------------------------------------------------------------------------
# temp_registry: isolated ~/.golem/projects.json
# ---------------------------------------------------------------------------


@pytest.fixture()
def temp_registry(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """Redirect registry I/O to a temp dir so real ~/.golem is never touched."""
    fake_golem = tmp_path / "fake_home" / ".golem"
    fake_golem.mkdir(parents=True)
    registry_file = fake_golem / "projects.json"

    def _fake_registry_path() -> Path:
        return registry_file

    monkeypatch.setattr(
        "golem_gateway.registry._registry_path", _fake_registry_path
    )
    return registry_file


# ---------------------------------------------------------------------------
# app / client: FastAPI + AsyncClient
# ---------------------------------------------------------------------------


@pytest.fixture()
def app() -> FastAPI:
    return _app


@pytest_asyncio.fixture()
async def client(app: FastAPI) -> AsyncClient:
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
