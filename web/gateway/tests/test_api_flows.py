"""Tests for GET/POST/PUT/DELETE /v1/projects/{id}/flows."""

from __future__ import annotations

import json
import logging
import os
import time
from pathlib import Path

import pytest
from httpx import ASGITransport, AsyncClient

import golem_gateway.api_flows as _flows_mod
from golem_gateway.forge_runner import ForgeRunner
from golem_gateway.main import app
from golem_gateway.registry import Project, ProjectRegistry

# Captured at import time, BEFORE the module-scoped autouse fixture below
# monkeypatches `_flows_mod._validate_with_forge` to a noop stub for every
# test in this file — the redaction test at the bottom needs the real
# implementation, not the stub.
_REAL_VALIDATE_WITH_FORGE = _flows_mod._validate_with_forge


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
    """Set app.state.registry/forge_runner if the lifespan hasn't done it yet."""
    if not hasattr(app.state, "registry"):
        app.state.registry = ProjectRegistry()
    # Fresh ForgeRunner per test — _flow_run_active looks this up via
    # getattr(request.app.state, "forge_runner", None); tests that need an
    # "active run" hit populate app.state.forge_runner._runs directly.
    app.state.forge_runner = ForgeRunner()


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

# Mixed type flow: input step + agent step.
_MIXED_TYPE_BODY = {
    "goal": "input then agent",
    "steps": [
        {"id": "inp", "task": "gather data", "soul": "", "type": "input"},
        {"id": "ag1", "task": "process data", "soul": "ryn", "type": "agent", "deps": ["inp"]},
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
async def test_post_flow_task_literal_brace_422(registered_project) -> None:
    """task containing a literal '},{' (bash steps-splitter boundary) → 422."""
    project_id, _ = registered_project
    body = {
        "goal": "brace breaker",
        "steps": [{"id": "s1", "task": "x},{y", "soul": "ryn"}],
    }
    resp = await _post(project_id, body)
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_post_flow_task_brace_with_space_before_comma_ok(registered_project) -> None:
    """Space BEFORE the comma ('} ,{') does not match the bash splitter — allowed."""
    project_id, _ = registered_project
    body = {
        "goal": "not a brace breaker",
        "steps": [{"id": "s1", "task": "x} ,{y", "soul": "ryn"}],
    }
    resp = await _post(project_id, body)
    assert resp.status_code == 201, resp.text


@pytest.mark.asyncio
async def test_post_flow_goto_unknown_id_422(registered_project) -> None:
    """on_fail goto:<id> referencing a non-existent step id must be rejected."""
    project_id, _ = registered_project
    body = {
        "goal": "ghost goto",
        "steps": [{"id": "s1", "task": "t1", "soul": "ryn", "on_fail": "goto:ghost"}],
    }
    resp = await _post(project_id, body)
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_post_flow_goto_existing_id_ok(registered_project) -> None:
    """on_fail goto:<id> referencing an existing step id must be accepted."""
    project_id, _ = registered_project
    body = {
        "goal": "valid goto",
        "steps": [
            {"id": "s1", "task": "t1", "soul": "ryn", "on_fail": "goto:s2"},
            {"id": "s2", "task": "t2", "soul": "ryn"},
        ],
    }
    resp = await _post(project_id, body)
    assert resp.status_code == 201, resp.text


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
async def test_put_flow_preserves_unchanged_step_results(registered_project) -> None:
    """PUT keeps status/run_id/output for steps whose definition is unchanged."""
    project_id, project_path = registered_project
    seeded = [
        {"id": "s1", "soul": "ryn", "task": "t1", "deps": [], "retry": 1,
         "approval": False, "on_fail": "abort", "type": "agent",
         "status": "done", "run_id": "run-1", "output": "result one"},
        {"id": "s2", "soul": "", "task": "t2", "deps": ["s1"], "retry": 1,
         "approval": False, "on_fail": "abort", "type": "agent",
         "status": "done", "run_id": "run-2", "output": "result two"},
    ]
    _write_flow(project_path, "flow_510_1", status="completed", steps=seeded)

    # PUT with identical task/soul/deps → results survive.
    body = {
        "goal": "edited goal",
        "steps": [
            {"id": "s1", "task": "t1", "soul": "ryn"},
            {"id": "s2", "task": "t2", "soul": "", "deps": ["s1"]},
        ],
    }
    resp = await _put(project_id, "flow_510_1", body)
    assert resp.status_code == 200, resp.text

    state = json.loads(
        (project_path / ".golem" / "flows" / "flow_510_1" / "state.json").read_text(encoding="utf-8")
    )
    by_id = {s["id"]: s for s in state["steps"]}
    assert state["goal"] == "edited goal"
    for sid, run, out in (("s1", "run-1", "result one"), ("s2", "run-2", "result two")):
        assert by_id[sid]["status"] == "done"
        assert by_id[sid]["run_id"] == run
        assert by_id[sid]["output"] == out


@pytest.mark.asyncio
async def test_put_flow_resets_changed_step(registered_project) -> None:
    """A step whose task changed loses its prior run state (cache invalidated)."""
    project_id, project_path = registered_project
    seeded = [
        {"id": "s1", "soul": "ryn", "task": "old task", "deps": [], "retry": 1,
         "approval": False, "on_fail": "abort", "type": "agent",
         "status": "done", "run_id": "run-1", "output": "stale"},
    ]
    _write_flow(project_path, "flow_520_2", status="completed", steps=seeded)

    body = {"goal": "g", "steps": [{"id": "s1", "task": "NEW task", "soul": "ryn"}]}
    resp = await _put(project_id, "flow_520_2", body)
    assert resp.status_code == 200, resp.text

    step = json.loads(
        (project_path / ".golem" / "flows" / "flow_520_2" / "state.json").read_text(encoding="utf-8")
    )["steps"][0]
    assert step["status"] == "pending"
    assert "run_id" not in step
    assert "output" not in step


@pytest.mark.asyncio
async def test_put_flow_invalidates_downstream_of_changed(registered_project) -> None:
    """Changing an upstream step also invalidates unchanged downstream steps."""
    project_id, project_path = registered_project
    seeded = [
        {"id": "s1", "soul": "ryn", "task": "t1", "deps": [], "retry": 1,
         "approval": False, "on_fail": "abort", "type": "agent",
         "status": "done", "run_id": "run-1", "output": "o1"},
        {"id": "s2", "soul": "ryn", "task": "t2", "deps": ["s1"], "retry": 1,
         "approval": False, "on_fail": "abort", "type": "agent",
         "status": "done", "run_id": "run-2", "output": "o2"},
    ]
    _write_flow(project_path, "flow_530_3", status="completed", steps=seeded)

    # s1 task changes; s2 definition unchanged but depends on s1 → also reset.
    body = {
        "goal": "g",
        "steps": [
            {"id": "s1", "task": "t1 CHANGED", "soul": "ryn"},
            {"id": "s2", "task": "t2", "soul": "ryn", "deps": ["s1"]},
        ],
    }
    resp = await _put(project_id, "flow_530_3", body)
    assert resp.status_code == 200, resp.text

    by_id = {
        s["id"]: s
        for s in json.loads(
            (project_path / ".golem" / "flows" / "flow_530_3" / "state.json").read_text(encoding="utf-8")
        )["steps"]
    }
    assert by_id["s1"]["status"] == "pending"
    assert by_id["s2"]["status"] == "pending"
    assert "output" not in by_id["s2"]


@pytest.mark.asyncio
async def test_put_flow_preserves_when_deps_reordered(registered_project) -> None:
    """deps compared as a set — reordering deps alone does not invalidate."""
    project_id, project_path = registered_project
    seeded = [
        {"id": "a", "soul": "ryn", "task": "ta", "deps": [], "retry": 1,
         "approval": False, "on_fail": "abort", "type": "agent", "status": "done"},
        {"id": "b", "soul": "ryn", "task": "tb", "deps": [], "retry": 1,
         "approval": False, "on_fail": "abort", "type": "agent", "status": "done"},
        {"id": "c", "soul": "ryn", "task": "tc", "deps": ["a", "b"], "retry": 1,
         "approval": False, "on_fail": "abort", "type": "agent",
         "status": "done", "run_id": "run-c", "output": "oc"},
    ]
    _write_flow(project_path, "flow_540_4", status="completed", steps=seeded)

    body = {
        "goal": "g",
        "steps": [
            {"id": "a", "task": "ta", "soul": "ryn"},
            {"id": "b", "task": "tb", "soul": "ryn"},
            {"id": "c", "task": "tc", "soul": "ryn", "deps": ["b", "a"]},  # reordered
        ],
    }
    resp = await _put(project_id, "flow_540_4", body)
    assert resp.status_code == 200, resp.text

    step_c = next(
        s
        for s in json.loads(
            (project_path / ".golem" / "flows" / "flow_540_4" / "state.json").read_text(encoding="utf-8")
        )["steps"]
        if s["id"] == "c"
    )
    assert step_c["status"] == "done"
    assert step_c["output"] == "oc"


@pytest.mark.asyncio
async def test_put_flow_resets_nonterminal_status_even_if_unchanged(registered_project) -> None:
    """Only 'done' is inherited — running/waiting_approval/failed reset to pending.

    Preserving a non-terminal status would re-introduce a permanent stall: a
    'running' step is never re-selected (not pending/approved) nor satisfies its
    dependents (not done), so the flow freezes forever.
    """
    project_id, project_path = registered_project
    seeded = [
        {"id": "r1", "soul": "ryn", "task": "t1", "deps": [], "retry": 1,
         "approval": False, "on_fail": "abort", "type": "agent",
         "status": "running", "run_id": "run-r1", "output": "partial"},
        {"id": "w1", "soul": "ryn", "task": "t2", "deps": [], "retry": 1,
         "approval": False, "on_fail": "abort", "type": "agent",
         "status": "waiting_approval"},
        {"id": "f1", "soul": "ryn", "task": "t3", "deps": [], "retry": 1,
         "approval": False, "on_fail": "abort", "type": "agent",
         "status": "failed", "output": "boom"},
    ]
    _write_flow(project_path, "flow_550_5", status="failed", steps=seeded)

    # Identical definitions → defs "unchanged", but statuses are non-terminal.
    body = {
        "goal": "g",
        "steps": [
            {"id": "r1", "task": "t1", "soul": "ryn"},
            {"id": "w1", "task": "t2", "soul": "ryn"},
            {"id": "f1", "task": "t3", "soul": "ryn"},
        ],
    }
    resp = await _put(project_id, "flow_550_5", body)
    assert resp.status_code == 200, resp.text

    by_id = {
        s["id"]: s
        for s in json.loads(
            (project_path / ".golem" / "flows" / "flow_550_5" / "state.json").read_text(encoding="utf-8")
        )["steps"]
    }
    for sid in ("r1", "w1", "f1"):
        assert by_id[sid]["status"] == "pending", f"{sid} must reset to pending"
        assert "run_id" not in by_id[sid], f"{sid} run_id must be dropped"
        assert "output" not in by_id[sid], f"{sid} output must be dropped"


@pytest.mark.asyncio
async def test_put_flow_retry_roundtrip(registered_project) -> None:
    """PUT with retry=3 must persist and be readable back via GET."""
    project_id, project_path = registered_project
    post_resp = await _post(project_id, _SIMPLE_BODY)
    assert post_resp.status_code == 201, post_resp.text
    flow_id = post_resp.json()["flow_id"]

    body = {
        "goal": "retry roundtrip",
        "steps": [{"id": "s1", "task": "t1", "soul": "ryn", "retry": 3}],
    }
    put_resp = await _put(project_id, flow_id, body)
    assert put_resp.status_code == 200, put_resp.text

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        get_resp = await client.get(f"/v1/projects/{project_id}/flows/{flow_id}")
    assert get_resp.status_code == 200
    assert get_resp.json()["steps"][0]["retry"] == 3


@pytest.mark.asyncio
async def test_get_flow_retry_defaults_to_1_when_missing(registered_project) -> None:
    """A bash-written state.json with no 'retry' key on a step defaults to 1."""
    project_id, project_path = registered_project
    _write_flow(
        project_path,
        "flow_retry_default",
        steps=[{"id": "s1", "soul": "ryn", "task": "t1", "deps": [], "status": "pending"}],
    )

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get(f"/v1/projects/{project_id}/flows/flow_retry_default")
    assert resp.status_code == 200
    assert resp.json()["steps"][0]["retry"] == 1


@pytest.mark.asyncio
async def test_list_flows_omits_output_detail_includes_it(registered_project) -> None:
    """list_flows() must null out step output; get_flow() must still return it."""
    project_id, project_path = registered_project
    steps_with_output = [
        {
            "id": "s1", "soul": "ryn", "task": "build", "deps": [],
            "retry": 1, "approval": False, "on_fail": "abort",
            "status": "done", "type": "agent", "output": "build succeeded",
        },
    ]
    _write_flow(project_path, "flow_list_output", goal="list output test", steps=steps_with_output)

    list_resp = await _get(project_id)
    assert list_resp.status_code == 200
    assert list_resp.json()[0]["steps"][0]["output"] is None

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        detail_resp = await client.get(f"/v1/projects/{project_id}/flows/flow_list_output")
    assert detail_resp.status_code == 200
    assert detail_resp.json()["steps"][0]["output"] == "build succeeded"


@pytest.mark.asyncio
async def test_put_flow_type_change_invalidates_cache(registered_project) -> None:
    """Same id, type agent->input must NOT inherit prior 'done' status/output."""
    project_id, project_path = registered_project
    seeded = [
        {"id": "s1", "soul": "ryn", "task": "t1", "deps": [], "retry": 1,
         "approval": False, "on_fail": "abort", "type": "agent",
         "status": "done", "run_id": "run-1", "output": "result one"},
    ]
    _write_flow(project_path, "flow_type_change", status="completed", steps=seeded)

    body = {
        "goal": "g",
        "steps": [{"id": "s1", "task": "t1", "soul": "ryn", "type": "input"}],
    }
    resp = await _put(project_id, "flow_type_change", body)
    assert resp.status_code == 200, resp.text

    step = json.loads(
        (project_path / ".golem" / "flows" / "flow_type_change" / "state.json").read_text(
            encoding="utf-8"
        )
    )["steps"][0]
    assert step["status"] == "pending"
    assert "run_id" not in step
    assert "output" not in step


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


# ---------------------------------------------------------------------------
# type / output field tests (new)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_post_flow_mixed_types_preserved(registered_project) -> None:
    """POST with mixed input/agent types — GET must reflect the types."""
    project_id, project_path = registered_project
    resp = await _post(project_id, _MIXED_TYPE_BODY)
    assert resp.status_code == 201, resp.text
    flow_id = resp.json()["flow_id"]

    # Verify persisted state.json contains correct types.
    state = json.loads(
        (project_path / ".golem" / "flows" / flow_id / "state.json").read_text(encoding="utf-8")
    )
    assert state["steps"][0]["type"] == "input"
    assert state["steps"][1]["type"] == "agent"

    # Verify GET response exposes types.
    get_resp = await _get(project_id)
    assert get_resp.status_code == 200
    flows = get_resp.json()
    assert len(flows) == 1
    steps = {s["id"]: s for s in flows[0]["steps"]}
    assert steps["inp"]["type"] == "input"
    assert steps["ag1"]["type"] == "agent"


@pytest.mark.asyncio
async def test_post_flow_input_step_no_deps_happy(registered_project) -> None:
    """input step with empty deps must be accepted (not a cycle, not a bad dep)."""
    project_id, _ = registered_project
    body = {
        "goal": "simple input",
        "steps": [{"id": "inp", "task": "collect input", "soul": "", "type": "input"}],
    }
    resp = await _post(project_id, body)
    assert resp.status_code == 201, resp.text


@pytest.mark.asyncio
async def test_post_flow_invalid_type_422(registered_project) -> None:
    """type value not in {input, agent} must return 422."""
    project_id, _ = registered_project
    body = {
        "goal": "bad type",
        "steps": [{"id": "s1", "task": "do it", "soul": "ryn", "type": "foo"}],
    }
    resp = await _post(project_id, body)
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_get_flow_output_passthrough(registered_project) -> None:
    """GET (detail) must expose output field when state.json contains it (runtime
    passthrough) — list_flows() nulls output (LOW-2), so this exercises the
    single-flow detail endpoint instead.
    """
    project_id, project_path = registered_project
    steps_with_output = [
        {
            "id": "s1", "soul": "ryn", "task": "build", "deps": [],
            "retry": 1, "approval": False, "on_fail": "abort",
            "status": "done", "type": "agent", "output": "build succeeded",
        },
        {
            "id": "s2", "soul": "", "task": "deploy", "deps": ["s1"],
            "retry": 1, "approval": False, "on_fail": "abort",
            "status": "pending", "type": "agent", "output": None,
        },
    ]
    _write_flow(project_path, "flow_output_test", goal="output test", steps=steps_with_output)

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get(f"/v1/projects/{project_id}/flows/flow_output_test")
    assert resp.status_code == 200
    steps = {s["id"]: s for s in resp.json()["steps"]}
    assert steps["s1"]["output"] == "build succeeded"
    assert steps["s2"]["output"] is None


@pytest.mark.asyncio
async def test_default_type_agent_when_missing(registered_project) -> None:
    """Steps in state.json without a type field default to 'agent' in GET response."""
    project_id, project_path = registered_project
    # _write_flow default steps have no 'type' key.
    _write_flow(project_path, "flow_no_type", goal="legacy flow")

    resp = await _get(project_id)
    assert resp.status_code == 200
    flows = resp.json()
    assert len(flows) == 1
    for step in flows[0]["steps"]:
        assert step["type"] == "agent"


# ---------------------------------------------------------------------------
# GET /flows/{flow_id} — 단건 조회 (실행 중 폴링 O(1) 경로, P4-1)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_get_single_flow(registered_project) -> None:
    project_id, project_path = registered_project
    _write_flow(project_path, "flow_100_1", goal="single", status="running")

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get(f"/v1/projects/{project_id}/flows/flow_100_1")
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["flow_id"] == "flow_100_1"
    assert data["goal"] == "single"
    assert len(data["steps"]) == 2


@pytest.mark.asyncio
async def test_get_single_flow_404(registered_project) -> None:
    project_id, _ = registered_project
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get(f"/v1/projects/{project_id}/flows/flow_999_9")
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_get_single_flow_invalid_id_400(registered_project) -> None:
    project_id, _ = registered_project
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get(f"/v1/projects/{project_id}/flows/notaflow!")
    assert resp.status_code == 400


# ---------------------------------------------------------------------------
# stderr redaction (BACKLOG.md P1) — _validate_with_forge is advisory-only
# (never raised as an HTTPException), but its returned string still must not
# carry a raw absolute path, since callers log/could surface it downstream.
# ---------------------------------------------------------------------------


class _FakeFailingProc:
    def __init__(self, stderr: bytes, returncode: int = 1) -> None:
        self.returncode = returncode
        self._stderr = stderr

    async def communicate(self) -> tuple[bytes, bytes]:
        return b"", self._stderr


@pytest.mark.asyncio
async def test_validate_with_forge_redacts_absolute_paths_and_logs_full_text(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    fake_forge_sh = tmp_path / "forge.sh"
    fake_forge_sh.write_text("#!/bin/bash\n", encoding="utf-8")
    monkeypatch.setattr(_flows_mod, "FORGE_SH_PATH", fake_forge_sh)

    project_dir = tmp_path / "redact_flow_project"
    (project_dir / ".golem").mkdir(parents=True)
    flow_dir = project_dir / ".golem" / "flows" / "flow_redact_1"
    flow_dir.mkdir(parents=True)
    state_path = flow_dir / "state.json"
    state_path.write_text("{}", encoding="utf-8")

    raw_stderr = (
        rb"C:\Users\secretuser\AppData\Local\golem\forge.sh: line 7: flow_validate: cycle found"
    )

    async def _fake_create_subprocess_exec(*args, **kwargs):  # noqa: ARG001
        return _FakeFailingProc(raw_stderr)

    monkeypatch.setattr(
        _flows_mod.asyncio, "create_subprocess_exec", _fake_create_subprocess_exec
    )

    with caplog.at_level(logging.ERROR, logger="golem_gateway.api_flows"):
        err = await _REAL_VALIDATE_WITH_FORGE(state_path, project_dir)

    assert err is not None
    assert "secretuser" not in err
    assert "C:\\Users" not in err
    assert len(err) <= 200

    full_logged = "\n".join(r.getMessage() for r in caplog.records)
    assert "secretuser" in full_logged


# ---------------------------------------------------------------------------
# HIGH-2: PUT/DELETE concurrency guards — active-run 409 + state.json.lock
# ---------------------------------------------------------------------------


def _make_active_forge_run(project_id: str, flow_id: str):
    import asyncio as _asyncio

    from golem_gateway.forge_runner import ForgeRun

    return ForgeRun(
        run_id="fake-active-run",
        command="flow",
        args=["run", flow_id],
        project_id=project_id,
        project_path=Path("."),
        proc=None,
        queue=_asyncio.Queue(),
        done=_asyncio.Event(),
        started_at=0.0,
    )


@pytest.mark.asyncio
async def test_put_flow_active_forge_run_409(registered_project) -> None:
    project_id, project_path = registered_project
    _write_flow(project_path, "flow_600_1", goal="active")
    app.state.forge_runner._runs["fake-active-run"] = _make_active_forge_run(
        project_id, "flow_600_1"
    )

    resp = await _put(project_id, "flow_600_1", _SIMPLE_BODY)
    assert resp.status_code == 409
    assert "running" in resp.json()["detail"]


@pytest.mark.asyncio
async def test_delete_flow_active_forge_run_409(registered_project) -> None:
    project_id, project_path = registered_project
    _write_flow(project_path, "flow_600_2", goal="active")
    app.state.forge_runner._runs["fake-active-run"] = _make_active_forge_run(
        project_id, "flow_600_2"
    )

    resp = await _delete(project_id, "flow_600_2")
    assert resp.status_code == 409
    flow_dir = project_path / ".golem" / "flows" / "flow_600_2"
    assert flow_dir.is_dir(), "flow dir must survive a rejected delete"


@pytest.mark.asyncio
async def test_put_flow_fresh_run_lock_409(registered_project) -> None:
    """A fresh (bash-CLI-held) run.lock dir blocks edits even with no in-process run."""
    project_id, project_path = registered_project
    _write_flow(project_path, "flow_610_1", goal="bash active")
    run_lock = project_path / ".golem" / "flows" / "flow_610_1" / "run.lock"
    run_lock.mkdir(parents=True)

    resp = await _put(project_id, "flow_610_1", _SIMPLE_BODY)
    assert resp.status_code == 409


@pytest.mark.asyncio
async def test_put_flow_stale_run_lock_allows_edit(registered_project) -> None:
    """A run.lock dir older than RUN_LOCK_STALE_SECONDS is presumed abandoned."""
    project_id, project_path = registered_project
    _write_flow(project_path, "flow_610_2", goal="stale bash run")
    run_lock = project_path / ".golem" / "flows" / "flow_610_2" / "run.lock"
    run_lock.mkdir(parents=True)
    old_time = time.time() - (_flows_mod.RUN_LOCK_STALE_SECONDS + 60)
    os.utime(run_lock, (old_time, old_time))

    resp = await _put(project_id, "flow_610_2", _SIMPLE_BODY)
    assert resp.status_code == 200, resp.text


@pytest.mark.asyncio
async def test_put_flow_locked_state_json_409(
    registered_project, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A freshly-held state.json.lock (another writer) blocks a concurrent PUT."""
    monkeypatch.setattr(_flows_mod, "STATE_LOCK_TIMEOUT_SECONDS", 0.2)
    project_id, project_path = registered_project
    _write_flow(project_path, "flow_620_1", goal="locked")
    lock_dir = project_path / ".golem" / "flows" / "flow_620_1" / "state.json.lock"
    lock_dir.mkdir(parents=True)

    resp = await _put(project_id, "flow_620_1", _SIMPLE_BODY)
    assert resp.status_code == 409
    assert "locked" in resp.json()["detail"]


@pytest.mark.asyncio
async def test_put_flow_stale_state_json_lock_reclaimed(
    registered_project, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A stale state.json.lock (older than STATE_LOCK_STALE_SECONDS) is reclaimed."""
    monkeypatch.setattr(_flows_mod, "STATE_LOCK_STALE_SECONDS", 0.05)
    project_id, project_path = registered_project
    _write_flow(project_path, "flow_620_2", goal="stale lock")
    lock_dir = project_path / ".golem" / "flows" / "flow_620_2" / "state.json.lock"
    lock_dir.mkdir(parents=True)
    old_time = time.time() - 10
    os.utime(lock_dir, (old_time, old_time))

    resp = await _put(project_id, "flow_620_2", _SIMPLE_BODY)
    assert resp.status_code == 200, resp.text


@pytest.mark.asyncio
async def test_put_flow_success_leaves_no_lock_dir(registered_project) -> None:
    project_id, project_path = registered_project
    _write_flow(project_path, "flow_620_3", goal="clean")

    resp = await _put(project_id, "flow_620_3", _SIMPLE_BODY)
    assert resp.status_code == 200, resp.text
    lock_dir = project_path / ".golem" / "flows" / "flow_620_3" / "state.json.lock"
    assert not lock_dir.exists()
