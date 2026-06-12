"""Tests for GET /v1/projects/{id}/runs and /runs/{run_id}/trace."""

from __future__ import annotations

import json
import time
import uuid
from pathlib import Path
from unittest.mock import patch

import pytest
from httpx import ASGITransport, AsyncClient

from golem_gateway.main import app
from golem_gateway.registry import ProjectRegistry


# ---------------------------------------------------------------------------
# Fixture: registered project (mirrors test_api_runs_contract.py pattern)
# ---------------------------------------------------------------------------

@pytest.fixture()
def registered_project(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    """Register a temp project and return (project_id, project_path)."""
    project_path = tmp_path / "test_project"
    project_path.mkdir()

    from golem_gateway.registry import Project
    from datetime import datetime, timezone

    fake_project = Project(
        id="proj-trace",
        name="Trace Test Project",
        path=str(project_path),
        created_at=datetime.now(tz=timezone.utc).isoformat(),
    )

    async def fake_get(self_or_project_id, project_id: str | None = None):
        pid = project_id if project_id is not None else self_or_project_id
        if pid == "proj-trace":
            return fake_project
        return None

    monkeypatch.setattr(ProjectRegistry, "get", fake_get)
    return ("proj-trace", project_path)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _write_run(project_path: Path, run_id: str, *, mtime_offset: float = 0.0,
               result: str = "success") -> None:
    """Write a minimal .jsonl + .meta.json pair for a run."""
    runs_dir = project_path / ".golem" / "runs"
    runs_dir.mkdir(parents=True, exist_ok=True)

    meta = {
        "run_id": run_id,
        "session_id": str(uuid.uuid4()),
        "soul": "ryn",
        "model": "claude-3-5-sonnet-20241022",
        "source": "gateway",
        "ts_start": "2026-06-12T00:00:00+00:00",
        "duration_ms": 1000,
        "tokens_in": 10,
        "tokens_out": 5,
        "tokens_cache": 0,
        "cost_usd": 0.001,
        "result": result,
        "tool_counts": {"bash": 1},
    }
    meta_path = runs_dir / f"{run_id}.meta.json"
    meta_path.write_text(json.dumps(meta), encoding="utf-8")

    jsonl_path = runs_dir / f"{run_id}.jsonl"
    jsonl_path.write_text(
        '{"type":"text","text":"hello"}\n{"type":"result","result":"success"}\n',
        encoding="utf-8",
    )

    if mtime_offset != 0.0:
        import os
        base = meta_path.stat().st_mtime + mtime_offset
        os.utime(meta_path, (base, base))
        os.utime(jsonl_path, (base, base))


# ---------------------------------------------------------------------------
# GET /v1/projects/{id}/runs
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_list_runs_empty(registered_project) -> None:
    project_id, _ = registered_project
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.get(f"/v1/projects/{project_id}/runs")
    assert resp.status_code == 200
    assert resp.json() == []


@pytest.mark.asyncio
async def test_list_runs_returns_metas(registered_project) -> None:
    project_id, project_path = registered_project
    rid = str(uuid.uuid4())
    _write_run(project_path, rid)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.get(f"/v1/projects/{project_id}/runs")

    assert resp.status_code == 200
    data = resp.json()
    assert len(data) == 1
    assert data[0]["run_id"] == rid
    assert data[0]["source"] == "gateway"


@pytest.mark.asyncio
async def test_list_runs_mtime_desc_order(registered_project) -> None:
    """Runs are returned newest-first (mtime descending)."""
    project_id, project_path = registered_project
    ids = [str(uuid.uuid4()) for _ in range(3)]
    for i, rid in enumerate(ids):
        _write_run(project_path, rid, mtime_offset=float(i))

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.get(f"/v1/projects/{project_id}/runs")

    assert resp.status_code == 200
    returned_ids = [r["run_id"] for r in resp.json()]
    # newest last written = ids[2], should appear first
    assert returned_ids[0] == ids[2]
    assert returned_ids[-1] == ids[0]


@pytest.mark.asyncio
async def test_list_runs_limit(registered_project) -> None:
    project_id, project_path = registered_project
    for i in range(5):
        _write_run(project_path, str(uuid.uuid4()), mtime_offset=float(i))

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.get(f"/v1/projects/{project_id}/runs?limit=2")

    assert resp.status_code == 200
    assert len(resp.json()) == 2


@pytest.mark.asyncio
async def test_list_runs_404_unknown_project() -> None:
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.get("/v1/projects/does-not-exist/runs")
    assert resp.status_code == 404


# ---------------------------------------------------------------------------
# GET /v1/projects/{id}/runs/{run_id}/trace
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_trace_returns_lines(registered_project) -> None:
    project_id, project_path = registered_project
    rid = str(uuid.uuid4())
    _write_run(project_path, rid)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.get(f"/v1/projects/{project_id}/runs/{rid}/trace")

    assert resp.status_code == 200
    data = resp.json()
    assert data["run_id"] == rid
    assert data["total_lines"] == 2
    assert data["offset"] == 0
    assert len(data["lines"]) == 2
    assert data["lines"][0]["type"] == "text"


@pytest.mark.asyncio
async def test_trace_pagination(registered_project) -> None:
    project_id, project_path = registered_project
    rid = str(uuid.uuid4())
    _write_run(project_path, rid)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.get(
            f"/v1/projects/{project_id}/runs/{rid}/trace?offset=1&limit=1"
        )

    assert resp.status_code == 200
    data = resp.json()
    assert data["total_lines"] == 2
    assert data["offset"] == 1
    assert len(data["lines"]) == 1
    assert data["lines"][0]["type"] == "result"


@pytest.mark.asyncio
async def test_trace_404_unknown_run(registered_project) -> None:
    project_id, _ = registered_project
    fake_id = str(uuid.uuid4())

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.get(f"/v1/projects/{project_id}/runs/{fake_id}/trace")

    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_trace_400_non_uuid_run_id(registered_project) -> None:
    """Non-UUID run_id must return 400 (path traversal guard G4)."""
    project_id, _ = registered_project

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.get(
            f"/v1/projects/{project_id}/runs/../../etc/passwd/trace"
        )

    # FastAPI path routing won't match the literal route for path-with-slashes,
    # so it may 404; but for a non-UUID string like "not-a-uuid" it must 400.
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp2 = await client.get(
            f"/v1/projects/{project_id}/runs/not-a-valid-uuid/trace"
        )
    assert resp2.status_code == 400


@pytest.mark.asyncio
async def test_trace_404_unknown_project() -> None:
    fake_run = str(uuid.uuid4())
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.get(f"/v1/projects/no-such-project/runs/{fake_run}/trace")
    assert resp.status_code == 404
