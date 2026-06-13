"""Tests for GET/POST/PUT/DELETE /v1/projects/{id}/flows."""

from __future__ import annotations

import json
import os
from pathlib import Path

import pytest
from httpx import ASGITransport, AsyncClient

from golem_gateway.main import app
from golem_gateway.registry import Project, ProjectRegistry


# ---------------------------------------------------------------------------
# Module-level autouse fixtures.
#
# 1. _prime_app_state: ensures app.state.registry exists without a full
#    lifespan (tests use bare ASGITransport, not the conftest client fixture).
# 2. _skip_forge_validate: stubs out the subprocess forge validate call.
#    The pure-Python cycle checker (_python_cycle_check) still runs; forge.sh
#    is skipped because tmp projects are not initialized GolemGarden projects
#    and forge.sh exits rc=1 for any non-golem directory.
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def _prime_app_state() -> None:
    """Set app.state.registry if the lifespan hasn't done it yet."""
    if not hasattr(app.state, "registry"):
        app.state.registry = ProjectRegistry()


@pytest.fixture(autouse=True)
def _skip_forge_validate(monkeypatch: pytest.MonkeyPatch) -> None:
    """Stub forge external validation — tmp projects lack GolemGarden context."""
    import golem_gateway.api_flows as _flows_mod

    async def _noop(state_path, project_path):  # noqa: ARG001
        return None

    monkeypatch.setattr(_flows_mod, "_validate_with_forge", _noop)


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


async def _post(project_id: str, body: dict):
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        return await client.post(f"/v1/projects/{project_id}/flows", json=body)


async def _put(project_id: str, flow_id: str, body: dict):
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        return await client.put(f"/v1/projects/{project_id}/flows/{flow_id}", json=body)


async def _delete(project_id: str, flow_id: str):
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        return await client.delete(f"/v1/projects/{project_id}/flows/{flow_id}")


# Minimal valid payload for a single-step flow.
_SIMPLE_BODY = {
    "goal": "do something",
    "steps": [{"id": "s1", "task": "run tests", "soul": "ryn"}],
}

# Two-step linear flow: s2 depends on s1.
_LINEAR_BODY = {
    "goal": "build and deploy",
    "steps": [
        {"id": "s1", "task": "build", "soul": "ryn"},
        {"id": "s2", "task": "deploy", "soul": "", "deps": ["s1"]},
    ],
}


# ---------------------------------------------------------------------------
# GET tests (regression — original 4 cases)
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


# ---------------------------------------------------------------------------
# POST tests
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_post_flow_happy_path(registered_project) -> None:
    """POST creates state.json with pending status and returns flow_id."""
    project_id, project_path = registered_project
    resp = await _post(project_id, _SIMPLE_BODY)
    assert resp.status_code == 201, resp.text
    data = resp.json()
    assert "flow_id" in data

    flow_id = data["flow_id"]
    state_path = project_path / ".golem" / "flows" / flow_id / "state.json"
    assert state_path.is_file(), "state.json must exist after POST"

    state = json.loads(state_path.read_text(encoding="utf-8"))
    assert state["flow_id"] == flow_id
    assert state["goal"] == _SIMPLE_BODY["goal"]
    assert state["status"] == "pending"
    assert len(state["steps"]) == 1
    assert state["steps"][0]["status"] == "pending"


@pytest.mark.asyncio
async def test_post_flow_all_steps_pending(registered_project) -> None:
    """Every step in the created state.json must have status=pending."""
    project_id, project_path = registered_project
    resp = await _post(project_id, _LINEAR_BODY)
    assert resp.status_code == 201, resp.text

    flow_id = resp.json()["flow_id"]
    state = json.loads(
        (project_path / ".golem" / "flows" / flow_id / "state.json").read_text(encoding="utf-8")
    )
    for step in state["steps"]:
        assert step["status"] == "pending", f"step {step['id']} not pending"


@pytest.mark.asyncio
async def test_post_flow_cycle_400(registered_project) -> None:
    """Cyclic deps (a→b, b→a) must be rejected with 400 and no directory left."""
    project_id, project_path = registered_project
    body = {
        "goal": "cycle",
        "steps": [
            {"id": "a", "task": "do a", "soul": "ryn", "deps": ["b"]},
            {"id": "b", "task": "do b", "soul": "ryn", "deps": ["a"]},
        ],
    }
    resp = await _post(project_id, body)
    assert resp.status_code == 400

    # Directory must have been cleaned up.
    flows_dir = project_path / ".golem" / "flows"
    leftover = [d for d in flows_dir.iterdir() if d.is_dir()] if flows_dir.is_dir() else []
    assert leftover == [], f"orphan flow dirs after cycle rejection: {leftover}"


@pytest.mark.asyncio
async def test_post_flow_invalid_on_fail_422(registered_project) -> None:
    """on_fail with unknown value must return 422."""
    project_id, _ = registered_project
    body = {
        "goal": "bad on_fail",
        "steps": [{"id": "s1", "task": "t", "soul": "ryn", "on_fail": "boom"}],
    }
    resp = await _post(project_id, body)
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_post_flow_invalid_retry_422(registered_project) -> None:
    """retry > 3 must return 422."""
    project_id, _ = registered_project
    body = {
        "goal": "bad retry",
        "steps": [{"id": "s1", "task": "t", "soul": "ryn", "retry": 9}],
    }
    resp = await _post(project_id, body)
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_post_flow_empty_task_422(registered_project) -> None:
    """Empty task string must return 422."""
    project_id, _ = registered_project
    body = {
        "goal": "empty task",
        "steps": [{"id": "s1", "task": "", "soul": "ryn"}],
    }
    resp = await _post(project_id, body)
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_post_flow_deps_unknown_id(registered_project) -> None:
    """deps referencing a non-existent step id must be rejected."""
    project_id, _ = registered_project
    body = {
        "goal": "bad deps",
        "steps": [
            {"id": "s1", "task": "do it", "soul": "ryn", "deps": ["ghost"]},
        ],
    }
    resp = await _post(project_id, body)
    # Model validator raises ValueError → Pydantic 422.
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_post_flow_unknown_project_404() -> None:
    resp = await _post("no-such-project", _SIMPLE_BODY)
    assert resp.status_code == 404


# ---------------------------------------------------------------------------
# PUT tests
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_put_flow_updates_content(registered_project) -> None:
    """PUT replaces goal/steps and resets status to pending."""
    project_id, project_path = registered_project

    # Create first.
    post_resp = await _post(project_id, _SIMPLE_BODY)
    assert post_resp.status_code == 201, post_resp.text
    flow_id = post_resp.json()["flow_id"]

    updated_body = {
        "goal": "updated goal",
        "steps": [
            {"id": "x1", "task": "new task", "soul": "rin"},
            {"id": "x2", "task": "follow-up", "soul": "", "deps": ["x1"]},
        ],
    }
    put_resp = await _put(project_id, flow_id, updated_body)
    assert put_resp.status_code == 200, put_resp.text
    assert put_resp.json()["flow_id"] == flow_id

    state = json.loads(
        (project_path / ".golem" / "flows" / flow_id / "state.json").read_text(encoding="utf-8")
    )
    assert state["flow_id"] == flow_id
    assert state["goal"] == "updated goal"
    assert state["status"] == "pending"
    assert len(state["steps"]) == 2
    for step in state["steps"]:
        assert step["status"] == "pending"


@pytest.mark.asyncio
async def test_put_flow_not_found_404(registered_project) -> None:
    project_id, _ = registered_project
    resp = await _put(project_id, "00000000-0000-0000-0000-000000000000", _SIMPLE_BODY)
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_put_flow_unknown_project_404() -> None:
    resp = await _put("no-such-project", "00000000-0000-0000-0000-000000000000", _SIMPLE_BODY)
    assert resp.status_code == 404


# ---------------------------------------------------------------------------
# DELETE tests
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_delete_flow_removes_directory(registered_project) -> None:
    """DELETE removes the flow directory; subsequent GET returns empty list."""
    project_id, project_path = registered_project

    post_resp = await _post(project_id, _SIMPLE_BODY)
    assert post_resp.status_code == 201, post_resp.text
    flow_id = post_resp.json()["flow_id"]

    flow_dir = project_path / ".golem" / "flows" / flow_id
    assert flow_dir.is_dir()

    del_resp = await _delete(project_id, flow_id)
    assert del_resp.status_code == 204, del_resp.text

    assert not flow_dir.exists(), "flow dir must be gone after DELETE"

    # Subsequent GET returns empty list.
    get_resp = await _get(project_id)
    assert get_resp.status_code == 200
    assert get_resp.json() == []


@pytest.mark.asyncio
async def test_delete_flow_not_found_404(registered_project) -> None:
    project_id, _ = registered_project
    resp = await _delete(project_id, "00000000-0000-0000-0000-000000000000")
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_delete_flow_unknown_project_404() -> None:
    resp = await _delete("no-such-project", "00000000-0000-0000-0000-000000000000")
    assert resp.status_code == 404
