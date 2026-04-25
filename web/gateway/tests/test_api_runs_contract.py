"""API contract tests for POST /v1/projects/{id}/runs.

No live claude subprocess is spawned. SessionManager.spawn_run is patched
to return a mock Run so we test HTTP request/response shapes only.
"""

from __future__ import annotations

import asyncio
import json
import time
import uuid
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from httpx import AsyncClient

from golem_gateway.events import RunCompletedEvent
from golem_gateway.main import app
from golem_gateway.registry import ProjectRegistry
from golem_gateway.session_manager import Run, SessionManager


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make_mock_run(session_id: str) -> Run:
    """Build a Run dataclass stub without touching asyncio subprocess."""
    run_id = str(uuid.uuid4())
    run = Run(
        run_id=run_id,
        session_id=session_id,
        soul_id="ryn",
        project_id="proj-test",
        proc=None,
        queue=asyncio.Queue(maxsize=10),
        done=asyncio.Event(),
        started_at=time.monotonic(),
    )
    run.done.set()  # mark as already completed so no background tasks needed
    return run


def _make_minimal_soul_detail(soul_id: str = "ryn"):
    """Return a minimal SoulDetail-like object."""
    from golem_gateway.souls import SoulDetail
    return SoulDetail(
        id=soul_id,
        name="Ryn",
        rank="Novice",
        specialty=["testing"],
        description="Testing SOUL.",
        content="# Ryn\nTesting SOUL.",
    )


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def _patch_app_state(monkeypatch: pytest.MonkeyPatch) -> None:
    """Ensure app.state has session_manager + registry without running lifespan."""
    from golem_gateway.forge_runner import ForgeRunner
    from golem_gateway.session_manager import SessionManager
    from golem_gateway.registry import ProjectRegistry

    if not hasattr(app.state, "session_manager"):
        app.state.session_manager = SessionManager()
    if not hasattr(app.state, "forge_runner"):
        app.state.forge_runner = ForgeRunner()
    if not hasattr(app.state, "registry"):
        app.state.registry = ProjectRegistry()


@pytest.fixture()
def registered_project(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    """Register a temp project in the app's registry and return (project_id, path)."""
    project_path = tmp_path / "test_project"
    project_path.mkdir()

    from golem_gateway.registry import Project
    from datetime import datetime, timezone

    fake_project = Project(
        id="proj-test",
        name="Test Project",
        path=str(project_path),
        created_at=datetime.now(tz=timezone.utc).isoformat(),
    )

    async def fake_get(self_or_project_id, project_id: str | None = None):
        # handles both bound (self, id) and unbound (id,) call patterns
        pid = project_id if project_id is not None else self_or_project_id
        if pid == "proj-test":
            return fake_project
        return None

    monkeypatch.setattr(ProjectRegistry, "get", fake_get)
    return ("proj-test", project_path)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_uuid_v4_validation_rejects_invalid_and_generates_fresh(
    registered_project, monkeypatch: pytest.MonkeyPatch
) -> None:
    """session_id='not-a-uuid' → server generates a valid UUID v4 and returns it."""
    project_id, project_path = registered_project
    valid_session_id = str(uuid.uuid4())
    mock_run = _make_mock_run(valid_session_id)

    async def fake_spawn_run(self, **kwargs):
        mock_run.session_id = kwargs.get("session_id", valid_session_id)
        return mock_run

    monkeypatch.setattr(SessionManager, "spawn_run", fake_spawn_run)

    soul_detail = _make_minimal_soul_detail()
    with patch("golem_gateway.souls.get_soul_by_id", return_value=soul_detail):
        with patch("golem_gateway.sessions_db.get_session_store") as mock_store_fn:
            mock_store = MagicMock()
            mock_store.get_user_assistant_count.return_value = 0
            mock_store.upsert_session.return_value = None
            mock_store.add_message.return_value = None
            mock_store_fn.return_value = mock_store

            from httpx import ASGITransport
            async with AsyncClient(
                transport=ASGITransport(app=app), base_url="http://test"
            ) as client:
                resp = await client.post(
                    f"/v1/projects/{project_id}/runs",
                    json={
                        "input": "hello",
                        "soul_id": "ryn",
                        "session_id": "not-a-uuid",
                    },
                )

    assert resp.status_code == 200
    body = resp.json()
    assert "run_id" in body
    assert "session_id" in body
    # The returned session_id must be a valid UUID v4
    parsed = uuid.UUID(body["session_id"])
    assert parsed.version == 4
    # Must NOT echo back the invalid session_id
    assert body["session_id"] != "not-a-uuid"


@pytest.mark.asyncio
async def test_413_oversized_input(
    registered_project, monkeypatch: pytest.MonkeyPatch
) -> None:
    project_id, _ = registered_project
    # 33 KiB > INPUT_MAX_BYTES (32 KiB)
    oversized_input = "x" * (33 * 1024)

    soul_detail = _make_minimal_soul_detail()
    with patch("golem_gateway.souls.get_soul_by_id", return_value=soul_detail):
        from httpx import ASGITransport
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            resp = await client.post(
                f"/v1/projects/{project_id}/runs",
                json={"input": oversized_input, "soul_id": "ryn"},
            )

    assert resp.status_code == 413


@pytest.mark.asyncio
async def test_404_unknown_project() -> None:
    from httpx import ASGITransport

    async def fake_get(self, project_id: str):
        return None

    with patch.object(ProjectRegistry, "get", fake_get):
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            resp = await client.post(
                "/v1/projects/does-not-exist/runs",
                json={"input": "hello", "soul_id": "ryn"},
            )

    assert resp.status_code == 404
    assert "does-not-exist" in resp.json()["detail"]


@pytest.mark.asyncio
async def test_404_unknown_soul(
    registered_project, monkeypatch: pytest.MonkeyPatch
) -> None:
    project_id, _ = registered_project
    with patch("golem_gateway.souls.get_soul_by_id", return_value=None):
        from httpx import ASGITransport
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            resp = await client.post(
                f"/v1/projects/{project_id}/runs",
                json={"input": "hello", "soul_id": "ghost"},
            )

    assert resp.status_code == 404
    assert "ghost" in resp.json()["detail"]


@pytest.mark.asyncio
async def test_valid_run_returns_run_id_and_session_id(
    registered_project, monkeypatch: pytest.MonkeyPatch
) -> None:
    project_id, project_path = registered_project
    expected_session_id = str(uuid.uuid4())
    mock_run = _make_mock_run(expected_session_id)

    async def fake_spawn_run(self, **kwargs):
        return mock_run

    monkeypatch.setattr(SessionManager, "spawn_run", fake_spawn_run)
    soul_detail = _make_minimal_soul_detail()

    with patch("golem_gateway.souls.get_soul_by_id", return_value=soul_detail):
        with patch("golem_gateway.sessions_db.get_session_store") as mock_store_fn:
            mock_store = MagicMock()
            mock_store.get_user_assistant_count.return_value = 0
            mock_store.upsert_session.return_value = None
            mock_store.add_message.return_value = None
            mock_store_fn.return_value = mock_store

            from httpx import ASGITransport
            async with AsyncClient(
                transport=ASGITransport(app=app), base_url="http://test"
            ) as client:
                resp = await client.post(
                    f"/v1/projects/{project_id}/runs",
                    json={
                        "input": "write a test",
                        "soul_id": "ryn",
                        "session_id": expected_session_id,
                    },
                )

    assert resp.status_code == 200
    body = resp.json()
    assert body["run_id"] == mock_run.run_id
    assert body["session_id"] == expected_session_id
