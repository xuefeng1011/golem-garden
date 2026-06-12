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


@pytest.fixture(autouse=True)
def temp_registry(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """Redirect registry I/O to a temp dir so real ~/.golem is never touched.

    autouse (2026-06-12): opt-in이던 시절 temp_registry 를 받지 않은 테스트
    (test_souls_extended 의 API 등록 테스트 2건)가 실제 ~/.golem/projects.json 에
    pytest 임시 경로 14건을 누적시킨 격리 누수가 라이브에서 발견됐다.
    모든 테스트에 자동 적용해 실 레지스트리 오염을 원천 차단한다.
    경로가 필요한 테스트는 기존처럼 인자로 받아 사용하면 된다.
    """
    # "registry_home": 일부 테스트(test_registry TestPathValidation)가 자체적으로
    # tmp_path/"fake_home" 을 mkdir 하므로 이름 충돌을 피해 별도 디렉토리를 쓴다
    fake_golem = tmp_path / "registry_home" / ".golem"
    fake_golem.mkdir(parents=True, exist_ok=True)
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
