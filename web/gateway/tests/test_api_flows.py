"""Tests for GET /v1/projects/{id}/flows."""

from __future__ import annotations

import json
import os
from pathlib import Path

import pytest
from httpx import ASGITransport, AsyncClient

from golem_gateway.main import app
from golem_gateway.registry import Project, ProjectRegistry


# ---------------------------------------------------------------------------
# Fixture: registered project (mirrors test_api_missions.py)
# ---------------------------------------------------------------------------


@pytest.fixture()
def registered_project(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    """Register a temp project and return (project_id, project_path)."""
    from datetime import datetime, timezone

    project_path = tmp_path / "test_project"
    project_path.mkdir()

    fake_project = Project(
        id="proj-flows",
        name="Flows Test Project",
        path=str(project_path),
        created_at=datetime.now(tz=timezone.utc).isoformat(),
    )

    async def fake_get(self_or_project_id, project_id: str | None = None):
        pid = project_id if project_id is not None else self_or_project_id
        if pid == "proj-flows":
            return fake_project
        return None

    monkeypatch.setattr(ProjectRegistry, "get", fake_get)
    return ("proj-flows", project_path)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _write_flow(
    project_path: Path,
    flow_id: str,
    *,
    goal: str = "test flow",
    status: str = "pending",
    steps: list[dict] | None = None,
    mtime_offset: float = 0.0,
) -> None:
    flow_dir = project_path / ".golem" / "flows" / flow_id
    flow_dir.mkdir(parents=True, exist_ok=True)
    state = {
        "flow_id": flow_id,
        "goal": goal,
        "created": "2026-06-13T00:00:00Z",
        "status": status,
        "steps": steps
        if steps is not None
        else [
            {"id": "s1", "soul": "ryn", "task": "t1", "deps": [],
             "retry": 1, "approval": False, "on_fail": "abort",
             "status": "pending"},
            {"id": "s2", "soul": "", "task": "t2", "deps": ["s1"],
             "retry": 0, "approval": True, "on_fail": "continue",
             "status": "pending"},
        ],
    }
    state_path = flow_dir / "state.json"
    state_path.write_text(json.dumps(state), encoding="utf-8")
    if mtime_offset != 0.0:
        base = flow_dir.stat().st_mtime + mtime_offset
        os.utime(flow_dir, (base, base))


async def _get(project_id: str):
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        return await client.get(f"/v1/projects/{project_id}/flows")


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_flows_empty_without_dir(registered_project) -> None:
    project_id, _ = registered_project
    resp = await _get(project_id)
    assert resp.status_code == 200
    assert resp.json() == []


@pytest.mark.asyncio
async def test_flows_content_and_order(registered_project) -> None:
    project_id, project_path = registered_project
    _write_flow(project_path, "flow_100_1", goal="old", mtime_offset=-10.0)
    _write_flow(project_path, "flow_200_2", goal="new", status="completed")

    resp = await _get(project_id)
    assert resp.status_code == 200
    flows = resp.json()
    assert [f["goal"] for f in flows] == ["new", "old"]
    first = flows[0]
    assert first["status"] == "completed"
    assert len(first["steps"]) == 2
    # empty-soul passthrough + approval/on_fail surface
    assert first["steps"][1]["soul"] == ""
    assert first["steps"][1]["approval"] is True
    assert first["steps"][1]["on_fail"] == "continue"
    assert first["steps"][1]["deps"] == ["s1"]


@pytest.mark.asyncio
async def test_flows_skips_corrupt_state(registered_project) -> None:
    project_id, project_path = registered_project
    _write_flow(project_path, "flow_300_3", goal="good")
    bad_dir = project_path / ".golem" / "flows" / "flow_400_4"
    bad_dir.mkdir(parents=True)
    (bad_dir / "state.json").write_text("{not json", encoding="utf-8")

    resp = await _get(project_id)
    assert resp.status_code == 200
    assert [f["goal"] for f in resp.json()] == ["good"]


@pytest.mark.asyncio
async def test_flows_unknown_project_404() -> None:
    resp = await _get("nope")
    assert resp.status_code == 404
