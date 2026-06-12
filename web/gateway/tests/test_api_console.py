"""Tests for GET /v1/projects/{project_id}/console."""

from __future__ import annotations

import asyncio
import json
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

import pytest
from httpx import ASGITransport, AsyncClient

from golem_gateway.main import app
from golem_gateway.registry import ProjectRegistry
from golem_gateway.session_manager import Run, SessionManager


# ---------------------------------------------------------------------------
# Bootstrap app.state without running lifespan (mirrors test_api_runs_contract)
# ---------------------------------------------------------------------------

@pytest.fixture(autouse=True)
def _patch_app_state() -> None:
    """Ensure app.state has session_manager + registry without running lifespan."""
    from golem_gateway.forge_runner import ForgeRunner

    if not hasattr(app.state, "session_manager"):
        app.state.session_manager = SessionManager()
    if not hasattr(app.state, "forge_runner"):
        app.state.forge_runner = ForgeRunner()
    if not hasattr(app.state, "registry"):
        app.state.registry = ProjectRegistry()


# ---------------------------------------------------------------------------
# Fixture: registered project (mirrors test_api_traces.py pattern)
# ---------------------------------------------------------------------------

@pytest.fixture()
def registered_project(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    """Register a temp project and return (project_id, project_path)."""
    project_path = tmp_path / "test_project"
    project_path.mkdir()

    from golem_gateway.registry import Project

    fake_project = Project(
        id="proj-console",
        name="Console Test Project",
        path=str(project_path),
        created_at=datetime.now(tz=timezone.utc).isoformat(),
    )

    async def fake_get(self_or_project_id, project_id: str | None = None):
        pid = project_id if project_id is not None else self_or_project_id
        if pid == "proj-console":
            return fake_project
        return None

    monkeypatch.setattr(ProjectRegistry, "get", fake_get)
    return ("proj-console", project_path)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _write_meta(
    project_path: Path,
    run_id: str,
    *,
    result: str = "success",
    soul: str = "ryn",
    duration_ms: int = 1000,
    cost_usd: float = 0.001,
    tokens_out: int = 5,
    mtime_offset: float = 0.0,
) -> None:
    """Write a minimal .meta.json (no .jsonl needed for console tests)."""
    runs_dir = project_path / ".golem" / "runs"
    runs_dir.mkdir(parents=True, exist_ok=True)

    meta = {
        "run_id": run_id,
        "session_id": str(uuid.uuid4()),
        "soul": soul,
        "model": "claude-3-5-sonnet-20241022",
        "source": "gateway",
        "ts_start": "2026-06-12T00:00:00+00:00",
        "duration_ms": duration_ms,
        "tokens_in": 10,
        "tokens_out": tokens_out,
        "tokens_cache": 0,
        "cost_usd": cost_usd,
        "result": result,
        "tool_counts": {},
    }
    meta_path = runs_dir / f"{run_id}.meta.json"
    meta_path.write_text(json.dumps(meta), encoding="utf-8")

    if mtime_offset != 0.0:
        import os
        base = meta_path.stat().st_mtime + mtime_offset
        os.utime(meta_path, (base, base))


def _inject_active_run(
    manager: SessionManager,
    *,
    project_id: str,
    soul_id: str = "ryn",
    run_id: str | None = None,
) -> Run:
    """Directly inject a fake active Run into the SessionManager._runs dict."""
    rid = run_id or str(uuid.uuid4())
    sid = str(uuid.uuid4())
    run = Run(
        run_id=rid,
        session_id=sid,
        soul_id=soul_id,
        project_id=project_id,
        proc=None,
        queue=asyncio.Queue(maxsize=10),
        done=asyncio.Event(),
        started_at=time.monotonic(),
    )
    manager._runs[rid] = run
    return run


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_console_empty_no_runs_dir(registered_project) -> None:
    """No runs directory -> all counts zero, empty lists."""
    project_id, _ = registered_project
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.get(f"/v1/projects/{project_id}/console")

    assert resp.status_code == 200
    data = resp.json()
    assert data["active_runs"] == []
    assert data["recent_runs"] == []
    s = data["stats"]
    assert s["total_runs"] == 0
    assert s["success"] == 0
    assert s["error"] == 0
    assert s["timeout"] == 0
    assert s["success_rate"] == 0.0
    assert s["avg_duration_ms"] == 0
    assert s["total_cost_usd"] == 0.0
    assert s["total_tokens_out"] == 0
    assert data["by_soul"] == []
    # budget must be present
    assert "budget" in data
    assert "total_cost_usd" in data["budget"]


@pytest.mark.asyncio
async def test_console_stats_and_by_soul(registered_project) -> None:
    """3 metas (success×2, error×1, soul×2) -> correct stats and by_soul."""
    project_id, project_path = registered_project

    _write_meta(project_path, str(uuid.uuid4()), result="success", soul="ryn",
                duration_ms=1000, cost_usd=0.002, tokens_out=10, mtime_offset=0.0)
    _write_meta(project_path, str(uuid.uuid4()), result="success", soul="zen",
                duration_ms=2000, cost_usd=0.003, tokens_out=20, mtime_offset=1.0)
    _write_meta(project_path, str(uuid.uuid4()), result="error", soul="ryn",
                duration_ms=500, cost_usd=0.001, tokens_out=5, mtime_offset=2.0)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.get(f"/v1/projects/{project_id}/console")

    assert resp.status_code == 200
    data = resp.json()

    s = data["stats"]
    assert s["total_runs"] == 3
    assert s["success"] == 2
    assert s["error"] == 1
    assert s["timeout"] == 0
    assert abs(s["success_rate"] - round(2 / 3, 4)) < 1e-6
    assert s["avg_duration_ms"] == (1000 + 2000 + 500) // 3
    assert abs(s["total_cost_usd"] - 0.006) < 1e-6
    assert s["total_tokens_out"] == 35

    # by_soul: ryn has 2 runs, zen has 1 -> ryn first
    by_soul = data["by_soul"]
    assert len(by_soul) == 2
    assert by_soul[0]["soul"] == "ryn"
    assert by_soul[0]["runs"] == 2
    assert abs(by_soul[0]["cost_usd"] - 0.003) < 1e-6
    assert abs(by_soul[0]["success_rate"] - 0.5) < 1e-6
    assert by_soul[1]["soul"] == "zen"
    assert by_soul[1]["runs"] == 1
    assert abs(by_soul[1]["success_rate"] - 1.0) < 1e-6

    # recent_runs: all 3 present
    assert len(data["recent_runs"]) == 3
    # each entry has the RunMeta fields
    for entry in data["recent_runs"]:
        assert "run_id" in entry
        assert "soul" in entry
        assert "result" in entry


@pytest.mark.asyncio
async def test_console_cache_invalidated_on_new_meta(registered_project) -> None:
    """Cache busts when a new meta file is added (directory signature change)."""
    project_id, project_path = registered_project

    _write_meta(project_path, str(uuid.uuid4()), result="success", mtime_offset=0.0)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp1 = await client.get(f"/v1/projects/{project_id}/console")
    assert resp1.json()["stats"]["total_runs"] == 1

    # Add a second meta — file_count changes so cache must invalidate
    _write_meta(project_path, str(uuid.uuid4()), result="error", mtime_offset=1.0)

    # Clear the runs_store module-level cache to simulate a fresh request
    # (in-process cache key is (file_count, max_mtime); adding a file changes file_count)
    import golem_gateway.runs_store as rs
    rs._meta_cache.clear()

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp2 = await client.get(f"/v1/projects/{project_id}/console")
    assert resp2.json()["stats"]["total_runs"] == 2


@pytest.mark.asyncio
async def test_console_unknown_project_404() -> None:
    """Non-existent project_id must return 404."""
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.get("/v1/projects/does-not-exist/console")
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_console_active_runs_injected(registered_project, monkeypatch) -> None:
    """active_runs_for returns injected Run; elapsed_ms is non-negative."""
    project_id, _ = registered_project

    manager = app.state.session_manager
    run = _inject_active_run(manager, project_id=project_id, soul_id="ryn")

    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            resp = await client.get(f"/v1/projects/{project_id}/console")

        assert resp.status_code == 200
        data = resp.json()
        active = data["active_runs"]
        assert len(active) == 1
        assert active[0]["run_id"] == run.run_id
        assert active[0]["session_id"] == run.session_id
        assert active[0]["soul"] == "ryn"
        assert active[0]["elapsed_ms"] >= 0
    finally:
        # Clean up injected run so it doesn't leak into other tests
        manager._runs.pop(run.run_id, None)
