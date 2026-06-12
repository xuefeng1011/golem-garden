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


# ---------------------------------------------------------------------------
# Tests for growth_log integration (Zen Phase M2)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_persist_growth_log_on_success(
    registered_project, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """On run.completed with success, _persist_assistant appends growth-log entry
    with result='success' and cost fields included (tokens_in > 0)."""
    project_id, project_path = registered_project
    session_id = str(uuid.uuid4())
    mock_run = _make_mock_run(session_id)

    # Simulate successful run completion with token usage
    mock_run.terminal_result = "success"
    mock_run.terminal_usage = {
        "input_tokens": 100,
        "output_tokens": 50,
        "cache_read_input_tokens": 10,
    }
    mock_run.terminal_duration_ms = 1234
    mock_run.session_model = "claude-3-5-sonnet-20241022"

    assistant_text = "Here is the result."

    # Mock the on_terminal callback capture
    captured_callback = []

    async def fake_spawn_run(self, **kwargs):
        # Capture the callback that was set
        captured_callback.append(None)
        return mock_run

    monkeypatch.setattr(SessionManager, "spawn_run", fake_spawn_run)
    soul_detail = _make_minimal_soul_detail()

    # Create growth-log directory
    growth_dir = project_path / ".golem" / "growth-log"
    growth_dir.mkdir(parents=True, exist_ok=True)

    with patch("golem_gateway.souls.get_soul_by_id", return_value=soul_detail):
        with patch("golem_gateway.sessions_db.get_session_store") as mock_store_fn:
            mock_store = MagicMock()
            mock_store.get_user_assistant_count.return_value = 0
            mock_store.upsert_session.return_value = None
            mock_store.add_message.return_value = None
            mock_store.add_messages_batch.return_value = None
            mock_store_fn.return_value = mock_store

            from httpx import ASGITransport

            async with AsyncClient(
                transport=ASGITransport(app=app), base_url="http://test"
            ) as client:
                resp = await client.post(
                    f"/v1/projects/{project_id}/runs",
                    json={
                        "input": "write a detailed test case",
                        "soul_id": "ryn",
                        "session_id": session_id,
                    },
                )

    assert resp.status_code == 200

    # Invoke the callback that was wired during create_run
    if mock_run.on_terminal:
        mock_run.on_terminal(assistant_text)

    # Verify growth-log JSONL was written
    log_file = growth_dir / "ryn.jsonl"
    assert log_file.exists(), f"growth-log file not created at {log_file}"

    # Parse the JSONL entry
    with log_file.open("r", encoding="utf-8") as f:
        line = f.read().strip()
    entry = json.loads(line)

    # Verify required fields
    assert entry["result"] == "success"
    assert entry["task"] == "write a detailed test case"
    assert "date" in entry
    assert entry["files_changed"] == 0
    assert entry["tests_passed"] == 0

    # Verify cost fields are present (tokens_in > 0)
    assert entry["tokens_in"] == 100
    assert entry["tokens_out"] == 50
    assert entry["tokens_cache"] == 10
    assert entry["model"] == "claude-3-5-sonnet-20241022"
    assert entry["duration_ms"] == 1234
    assert "cost_usd" in entry


@pytest.mark.asyncio
async def test_persist_growth_log_on_failure(
    registered_project, monkeypatch: pytest.MonkeyPatch
) -> None:
    """On run.failed, result='fail' and cost fields omitted (or zeros)."""
    project_id, project_path = registered_project
    session_id = str(uuid.uuid4())
    mock_run = _make_mock_run(session_id)

    # Simulate failed run
    mock_run.terminal_result = "fail"
    mock_run.terminal_usage = {}  # no tokens on failure
    mock_run.terminal_duration_ms = 0
    mock_run.session_model = ""

    assistant_text = "Error: operation failed."

    async def fake_spawn_run(self, **kwargs):
        return mock_run

    monkeypatch.setattr(SessionManager, "spawn_run", fake_spawn_run)
    soul_detail = _make_minimal_soul_detail()

    growth_dir = project_path / ".golem" / "growth-log"
    growth_dir.mkdir(parents=True, exist_ok=True)

    with patch("golem_gateway.souls.get_soul_by_id", return_value=soul_detail):
        with patch("golem_gateway.sessions_db.get_session_store") as mock_store_fn:
            mock_store = MagicMock()
            mock_store.get_user_assistant_count.return_value = 0
            mock_store.upsert_session.return_value = None
            mock_store.add_message.return_value = None
            mock_store.add_messages_batch.return_value = None
            mock_store_fn.return_value = mock_store

            from httpx import ASGITransport

            async with AsyncClient(
                transport=ASGITransport(app=app), base_url="http://test"
            ) as client:
                resp = await client.post(
                    f"/v1/projects/{project_id}/runs",
                    json={
                        "input": "run failing task",
                        "soul_id": "ryn",
                        "session_id": session_id,
                    },
                )

    assert resp.status_code == 200

    if mock_run.on_terminal:
        mock_run.on_terminal(assistant_text)

    log_file = project_path / ".golem" / "growth-log" / "ryn.jsonl"
    assert log_file.exists()

    with log_file.open("r", encoding="utf-8") as f:
        line = f.read().strip()
    entry = json.loads(line)

    # Verify result is fail
    assert entry["result"] == "fail"
    assert entry["task"] == "run failing task"

    # Cost fields should NOT be present (tokens_in == 0)
    assert "tokens_in" not in entry
    assert "tokens_out" not in entry
    assert "tokens_cache" not in entry
    assert "model" not in entry
    assert "duration_ms" not in entry
    assert "cost_usd" not in entry


@pytest.mark.asyncio
async def test_persist_growth_log_swallows_errors(
    registered_project, monkeypatch: pytest.MonkeyPatch
) -> None:
    """If growth-log write fails (e.g., permission denied), callback does NOT
    crash and HTTP response is still returned successfully."""
    project_id, project_path = registered_project
    session_id = str(uuid.uuid4())
    mock_run = _make_mock_run(session_id)

    mock_run.terminal_result = "success"
    mock_run.terminal_usage = {"input_tokens": 100}
    mock_run.terminal_duration_ms = 500
    mock_run.session_model = "claude-3-5-sonnet-20241022"

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
            mock_store.add_messages_batch.return_value = None
            mock_store_fn.return_value = mock_store

            # Patch growth_log.append_entry to simulate write failure
            with patch("golem_gateway.growth_log.append_entry", return_value=False):
                from httpx import ASGITransport

                async with AsyncClient(
                    transport=ASGITransport(app=app), base_url="http://test"
                ) as client:
                    resp = await client.post(
                        f"/v1/projects/{project_id}/runs",
                        json={
                            "input": "task",
                            "soul_id": "ryn",
                            "session_id": session_id,
                        },
                    )

    # HTTP response succeeds despite growth-log failure
    assert resp.status_code == 200
    assert "run_id" in resp.json()

    # Invoke callback; it should not raise
    if mock_run.on_terminal:
        try:
            mock_run.on_terminal("assistant text")
        except Exception as e:
            pytest.fail(f"on_terminal callback raised: {e}")


@pytest.mark.asyncio
async def test_persist_growth_log_task_truncation(
    registered_project, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Task longer than 80 chars is truncated; newlines stripped."""
    project_id, project_path = registered_project
    session_id = str(uuid.uuid4())
    mock_run = _make_mock_run(session_id)

    mock_run.terminal_result = "success"
    mock_run.terminal_usage = {"input_tokens": 50}
    mock_run.terminal_duration_ms = 100
    mock_run.session_model = "claude-3-5-sonnet-20241022"

    long_input = "x" * 100 + "\nwith newlines\rand carriage returns"

    async def fake_spawn_run(self, **kwargs):
        return mock_run

    monkeypatch.setattr(SessionManager, "spawn_run", fake_spawn_run)
    soul_detail = _make_minimal_soul_detail()

    growth_dir = project_path / ".golem" / "growth-log"
    growth_dir.mkdir(parents=True, exist_ok=True)

    with patch("golem_gateway.souls.get_soul_by_id", return_value=soul_detail):
        with patch("golem_gateway.sessions_db.get_session_store") as mock_store_fn:
            mock_store = MagicMock()
            mock_store.get_user_assistant_count.return_value = 0
            mock_store.upsert_session.return_value = None
            mock_store.add_message.return_value = None
            mock_store.add_messages_batch.return_value = None
            mock_store_fn.return_value = mock_store

            from httpx import ASGITransport

            async with AsyncClient(
                transport=ASGITransport(app=app), base_url="http://test"
            ) as client:
                resp = await client.post(
                    f"/v1/projects/{project_id}/runs",
                    json={
                        "input": long_input,
                        "soul_id": "ryn",
                        "session_id": session_id,
                    },
                )

    assert resp.status_code == 200

    if mock_run.on_terminal:
        mock_run.on_terminal("response")

    log_file = project_path / ".golem" / "growth-log" / "ryn.jsonl"
    with log_file.open("r", encoding="utf-8") as f:
        line = f.read().strip()
    entry = json.loads(line)

    # Task should be truncated to 80 chars and newlines stripped
    assert len(entry["task"]) == 80
    assert "\n" not in entry["task"]
    assert "\r" not in entry["task"]
    # First 80 chars of input with newlines removed
    expected = (long_input.replace("\n", " ").replace("\r", "").strip())[:80]
    assert entry["task"] == expected


@pytest.mark.asyncio
async def test_persist_growth_log_zero_tokens_omits_cost_fields(
    registered_project, monkeypatch: pytest.MonkeyPatch
) -> None:
    """When tokens_in=0, cost fields (tokens_*, model, duration_ms) are omitted."""
    project_id, project_path = registered_project
    session_id = str(uuid.uuid4())
    mock_run = _make_mock_run(session_id)

    mock_run.terminal_result = "success"
    mock_run.terminal_usage = {"input_tokens": 0, "output_tokens": 0}
    mock_run.terminal_duration_ms = 0
    mock_run.session_model = ""

    async def fake_spawn_run(self, **kwargs):
        return mock_run

    monkeypatch.setattr(SessionManager, "spawn_run", fake_spawn_run)
    soul_detail = _make_minimal_soul_detail()

    growth_dir = project_path / ".golem" / "growth-log"
    growth_dir.mkdir(parents=True, exist_ok=True)

    with patch("golem_gateway.souls.get_soul_by_id", return_value=soul_detail):
        with patch("golem_gateway.sessions_db.get_session_store") as mock_store_fn:
            mock_store = MagicMock()
            mock_store.get_user_assistant_count.return_value = 0
            mock_store.upsert_session.return_value = None
            mock_store.add_message.return_value = None
            mock_store.add_messages_batch.return_value = None
            mock_store_fn.return_value = mock_store

            from httpx import ASGITransport

            async with AsyncClient(
                transport=ASGITransport(app=app), base_url="http://test"
            ) as client:
                resp = await client.post(
                    f"/v1/projects/{project_id}/runs",
                    json={
                        "input": "task with no tokens",
                        "soul_id": "ryn",
                        "session_id": session_id,
                    },
                )

    assert resp.status_code == 200

    if mock_run.on_terminal:
        mock_run.on_terminal("")

    log_file = project_path / ".golem" / "growth-log" / "ryn.jsonl"
    with log_file.open("r", encoding="utf-8") as f:
        line = f.read().strip()
    entry = json.loads(line)

    # Only 5 required fields, no cost fields
    assert "tokens_in" not in entry
    assert "tokens_out" not in entry
    assert "tokens_cache" not in entry
    assert "model" not in entry
    assert "duration_ms" not in entry
    assert "cost_usd" not in entry
    # But required fields present
    assert "date" in entry
    assert "task" in entry
    assert "result" in entry
    assert "files_changed" in entry
    assert "tests_passed" in entry


@pytest.mark.asyncio
async def test_persist_growth_log_captures_soul_id_from_request(
    registered_project, monkeypatch: pytest.MonkeyPatch
) -> None:
    """The soul_id is captured directly from body.soul_id (not DB lookup)."""
    project_id, project_path = registered_project
    session_id = str(uuid.uuid4())
    mock_run = _make_mock_run(session_id)

    mock_run.terminal_result = "success"
    mock_run.terminal_usage = {"input_tokens": 50}
    mock_run.terminal_duration_ms = 100
    mock_run.session_model = "test-model"

    async def fake_spawn_run(self, **kwargs):
        return mock_run

    monkeypatch.setattr(SessionManager, "spawn_run", fake_spawn_run)
    # Use a different soul_id in the detail vs request
    soul_detail = _make_minimal_soul_detail(soul_id="custom-soul")

    growth_dir = project_path / ".golem" / "growth-log"
    growth_dir.mkdir(parents=True, exist_ok=True)

    with patch("golem_gateway.souls.get_soul_by_id", return_value=soul_detail):
        with patch("golem_gateway.sessions_db.get_session_store") as mock_store_fn:
            mock_store = MagicMock()
            mock_store.get_user_assistant_count.return_value = 0
            mock_store.upsert_session.return_value = None
            mock_store.add_message.return_value = None
            mock_store.add_messages_batch.return_value = None
            mock_store_fn.return_value = mock_store

            from httpx import ASGITransport

            async with AsyncClient(
                transport=ASGITransport(app=app), base_url="http://test"
            ) as client:
                # Request explicitly uses "custom-soul"
                resp = await client.post(
                    f"/v1/projects/{project_id}/runs",
                    json={
                        "input": "test",
                        "soul_id": "custom-soul",
                        "session_id": session_id,
                    },
                )

    assert resp.status_code == 200

    if mock_run.on_terminal:
        mock_run.on_terminal("response")

    # Verify log file created with soul_id from request
    log_file = project_path / ".golem" / "growth-log" / "custom-soul.jsonl"
    assert log_file.exists(), "Log file should be named after request soul_id"


@pytest.mark.asyncio
async def test_persist_growth_log_no_terminal_result_defaults_to_fail(
    registered_project, monkeypatch: pytest.MonkeyPatch
) -> None:
    """If terminal_result is empty string, defaults to 'fail' in growth-log."""
    project_id, project_path = registered_project
    session_id = str(uuid.uuid4())
    mock_run = _make_mock_run(session_id)

    # terminal_result not set (defaults to "")
    mock_run.terminal_result = ""
    mock_run.terminal_usage = {}
    mock_run.terminal_duration_ms = 0
    mock_run.session_model = ""

    async def fake_spawn_run(self, **kwargs):
        return mock_run

    monkeypatch.setattr(SessionManager, "spawn_run", fake_spawn_run)
    soul_detail = _make_minimal_soul_detail()

    growth_dir = project_path / ".golem" / "growth-log"
    growth_dir.mkdir(parents=True, exist_ok=True)

    with patch("golem_gateway.souls.get_soul_by_id", return_value=soul_detail):
        with patch("golem_gateway.sessions_db.get_session_store") as mock_store_fn:
            mock_store = MagicMock()
            mock_store.get_user_assistant_count.return_value = 0
            mock_store.upsert_session.return_value = None
            mock_store.add_message.return_value = None
            mock_store.add_messages_batch.return_value = None
            mock_store_fn.return_value = mock_store

            from httpx import ASGITransport

            async with AsyncClient(
                transport=ASGITransport(app=app), base_url="http://test"
            ) as client:
                resp = await client.post(
                    f"/v1/projects/{project_id}/runs",
                    json={
                        "input": "test",
                        "soul_id": "ryn",
                        "session_id": session_id,
                    },
                )

    assert resp.status_code == 200

    if mock_run.on_terminal:
        mock_run.on_terminal("")

    log_file = project_path / ".golem" / "growth-log" / "ryn.jsonl"
    with log_file.open("r", encoding="utf-8") as f:
        line = f.read().strip()
    entry = json.loads(line)

    # Should default to "fail" per line 219 of api_runs.py
    assert entry["result"] == "fail"


# ---------------------------------------------------------------------------
# Per-run model override (C4)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_model_override_rejects_unknown_model(registered_project) -> None:
    """model='gpt-5' → 422 (whitelist: opus/sonnet/haiku or claude-*)."""
    project_id, _ = registered_project
    from httpx import ASGITransport
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        resp = await client.post(
            f"/v1/projects/{project_id}/runs",
            json={"input": "hello", "soul_id": "ryn", "model": "gpt-5"},
        )
    assert resp.status_code == 422


@pytest.mark.asyncio
@pytest.mark.parametrize("model", ["haiku", "claude-sonnet-4-6"])
async def test_model_override_forwarded_to_spawn(
    registered_project, monkeypatch: pytest.MonkeyPatch, model: str
) -> None:
    """Valid model value must reach SessionManager.spawn_run(model=...)."""
    project_id, _ = registered_project
    valid_session_id = str(uuid.uuid4())
    mock_run = _make_mock_run(valid_session_id)
    captured: dict = {}

    async def fake_spawn_run(self, **kwargs):
        captured.update(kwargs)
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
                    json={"input": "hello", "soul_id": "ryn", "model": model},
                )

    assert resp.status_code == 200
    assert captured.get("model") == model
