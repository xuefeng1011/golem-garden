"""Tests for GET /v1/projects/{id}/missions."""

from __future__ import annotations

import json
import os
import time
from pathlib import Path

import pytest
from httpx import ASGITransport, AsyncClient

from golem_gateway.main import app
from golem_gateway.registry import Project, ProjectRegistry


# ---------------------------------------------------------------------------
# Fixture: registered project
# ---------------------------------------------------------------------------


@pytest.fixture()
def registered_project(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    """Register a temp project and return (project_id, project_path)."""
    from datetime import datetime, timezone

    project_path = tmp_path / "test_project"
    project_path.mkdir()

    fake_project = Project(
        id="proj-missions",
        name="Missions Test Project",
        path=str(project_path),
        created_at=datetime.now(tz=timezone.utc).isoformat(),
    )

    async def fake_get(self_or_project_id, project_id: str | None = None):
        pid = project_id if project_id is not None else self_or_project_id
        if pid == "proj-missions":
            return fake_project
        return None

    monkeypatch.setattr(ProjectRegistry, "get", fake_get)
    return ("proj-missions", project_path)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _write_mission(
    project_path: Path,
    mission_id: str,
    *,
    goal: str = "do something",
    status: str = "completed",
    created: str = "2026-06-05T12:50:00",
    tasks: list[dict] | None = None,
    mtime_offset: float = 0.0,
    corrupt: bool = False,
) -> Path:
    """Write a mission state.json under .golem/missions/{mission_id}/."""
    missions_dir = project_path / ".golem" / "missions"
    msn_dir = missions_dir / mission_id
    msn_dir.mkdir(parents=True, exist_ok=True)
    state_path = msn_dir / "state.json"

    if corrupt:
        state_path.write_text("{not valid json", encoding="utf-8")
    else:
        if tasks is None:
            tasks = [{"idx": 0, "task": "default task", "soul": "ryn", "status": "done"}]
        state = {
            "id": mission_id,
            "goal": goal,
            "status": status,
            "created": created,
            "seq": "1780663800964989200",  # must be excluded from response
            "tasks": tasks,
        }
        state_path.write_text(json.dumps(state), encoding="utf-8")

    if mtime_offset != 0.0:
        base = msn_dir.stat().st_mtime + mtime_offset
        os.utime(msn_dir, (base, base))
        os.utime(state_path, (base, base))

    return state_path


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_missions_no_dir_returns_empty(registered_project) -> None:
    """No .golem/missions directory -> []."""
    project_id, _ = registered_project
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.get(f"/v1/projects/{project_id}/missions")
    assert resp.status_code == 200
    assert resp.json() == []


@pytest.mark.asyncio
async def test_missions_content_and_order(registered_project) -> None:
    """Two missions: newest first, tasks present, seq excluded."""
    project_id, project_path = registered_project

    tasks_a = [{"idx": 0, "task": "write code", "soul": "ryn", "status": "done"}]
    tasks_b = [
        {"idx": 0, "task": "plan", "soul": "", "status": "done"},
        {"idx": 1, "task": "build", "soul": "ryn", "status": "in_progress"},
    ]

    _write_mission(project_path, "msn_1000_old", goal="old mission",
                   status="completed", tasks=tasks_a, mtime_offset=0.0)
    _write_mission(project_path, "msn_2000_new", goal="new mission",
                   status="active", tasks=tasks_b, mtime_offset=10.0)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.get(f"/v1/projects/{project_id}/missions")

    assert resp.status_code == 200
    data = resp.json()
    assert len(data) == 2

    # Newest first
    assert data[0]["id"] == "msn_2000_new"
    assert data[0]["goal"] == "new mission"
    assert data[0]["status"] == "active"
    assert len(data[0]["tasks"]) == 2
    assert data[0]["tasks"][0]["soul"] == ""   # empty string passthrough
    assert data[0]["tasks"][1]["status"] == "in_progress"

    # seq must NOT appear in response
    assert "seq" not in data[0]

    assert data[1]["id"] == "msn_1000_old"
    assert data[1]["tasks"][0]["soul"] == "ryn"
    assert data[1]["tasks"][0]["status"] == "done"


@pytest.mark.asyncio
async def test_missions_corrupt_skipped(registered_project) -> None:
    """Corrupt state.json is skipped; healthy mission still returned."""
    project_id, project_path = registered_project

    _write_mission(project_path, "msn_good_001", goal="healthy", status="completed",
                   mtime_offset=0.0)
    _write_mission(project_path, "msn_bad_002", corrupt=True, mtime_offset=5.0)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.get(f"/v1/projects/{project_id}/missions")

    assert resp.status_code == 200
    data = resp.json()
    assert len(data) == 1
    assert data[0]["id"] == "msn_good_001"


@pytest.mark.asyncio
async def test_missions_limit(registered_project) -> None:
    """limit parameter caps results."""
    project_id, project_path = registered_project

    for i in range(5):
        _write_mission(project_path, f"msn_{i:04d}_x", goal=f"mission {i}",
                       status="completed", mtime_offset=float(i))

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.get(f"/v1/projects/{project_id}/missions?limit=3")

    assert resp.status_code == 200
    assert len(resp.json()) == 3


@pytest.mark.asyncio
async def test_missions_404_unknown_project() -> None:
    """Unknown project_id -> 404."""
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.get("/v1/projects/does-not-exist/missions")
    assert resp.status_code == 404
