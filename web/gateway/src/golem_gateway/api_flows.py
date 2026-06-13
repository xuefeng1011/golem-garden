"""APIRouter for flow listing and management (Flow Engine read/write view).

GET    /v1/projects/{project_id}/flows
POST   /v1/projects/{project_id}/flows
PUT    /v1/projects/{project_id}/flows/{flow_id}
DELETE /v1/projects/{project_id}/flows/{flow_id}
"""

from __future__ import annotations

import asyncio
import heapq
import json
import logging
import os
import re
import shutil
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel, field_validator, model_validator

from golem_gateway.config import BASH_BIN, FORGE_SH_BASH_PATH, FORGE_SH_PATH, to_bash_path
from golem_gateway.registry import ProjectRegistry

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1/projects/{project_id}", tags=["flows"])

# Safe flow directory name: uuid or flow_<epoch>_<pid> fallback (lib/flow-dag.sh).
_FLOW_DIR_RE = re.compile(r"^(flow_[A-Za-z0-9_]+|[0-9a-f-]{36})$", re.IGNORECASE)

# Valid on_fail values pattern.
_ON_FAIL_RE = re.compile(r"^(abort|continue|goto:[A-Za-z0-9_-]+)$")

# Valid step id pattern.
_STEP_ID_RE = re.compile(r"^[A-Za-z0-9_-]+$")


# ---------------------------------------------------------------------------
# Models — read (response)
# ---------------------------------------------------------------------------


class FlowStep(BaseModel):
    id: str
    soul: str
    task: str
    deps: list[str]
    status: str
    approval: bool = False
    on_fail: str = "abort"
    # 단계 실행 트래젝토리 링크 (단계별 결과 보기) — 미실행 단계는 None
    run_id: str | None = None
    type: str = "agent"
    output: str | None = None


class FlowSummary(BaseModel):
    flow_id: str
    goal: str
    status: str
    created: str
    steps: list[FlowStep]


# ---------------------------------------------------------------------------
# Models — write (request)
# ---------------------------------------------------------------------------


_STEP_TYPE_VALID = {"input", "agent"}


class FlowStepInput(BaseModel):
    id: str
    soul: str = ""
    task: str
    deps: list[str] = []
    retry: int = 1
    approval: bool = False
    on_fail: str = "abort"
    type: str = "agent"

    @field_validator("id")
    @classmethod
    def validate_id(cls, v: str) -> str:
        if not _STEP_ID_RE.match(v):
            raise ValueError(
                f"step id {v!r} must match ^[A-Za-z0-9_-]+$"
            )
        return v

    @field_validator("task")
    @classmethod
    def validate_task(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("task must not be empty")
        return v

    @field_validator("retry")
    @classmethod
    def validate_retry(cls, v: int) -> int:
        if v < 0 or v > 3:
            raise ValueError("retry must be between 0 and 3")
        return v

    @field_validator("on_fail")
    @classmethod
    def validate_on_fail(cls, v: str) -> str:
        if not _ON_FAIL_RE.match(v):
            raise ValueError(
                f"on_fail {v!r} must be abort|continue|goto:<id>"
            )
        return v

    @field_validator("type")
    @classmethod
    def validate_type(cls, v: str) -> str:
        if v not in _STEP_TYPE_VALID:
            raise ValueError(
                f"type {v!r} must be one of: {sorted(_STEP_TYPE_VALID)}"
            )
        return v


class FlowWriteRequest(BaseModel):
    goal: str
    steps: list[FlowStepInput]

    @field_validator("goal")
    @classmethod
    def validate_goal(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("goal must not be empty")
        return v

    @field_validator("steps")
    @classmethod
    def validate_steps_nonempty(cls, v: list[FlowStepInput]) -> list[FlowStepInput]:
        if not v:
            raise ValueError("steps must contain at least one step")
        return v

    @model_validator(mode="after")
    def validate_step_graph(self) -> "FlowWriteRequest":
        ids = [s.id for s in self.steps]
        # Uniqueness check.
        if len(ids) != len(set(ids)):
            seen: set[str] = set()
            dupes = [i for i in ids if i in seen or seen.add(i)]  # type: ignore[func-returns-value]
            raise ValueError(f"duplicate step ids: {dupes}")
        id_set = set(ids)
        # Deps reference check.
        for step in self.steps:
            bad_deps = [d for d in step.deps if d not in id_set]
            if bad_deps:
                raise ValueError(
                    f"step {step.id!r} deps reference unknown ids: {bad_deps}"
                )
        return self


# ---------------------------------------------------------------------------
# Dependency
# ---------------------------------------------------------------------------


def _get_registry(request: Request) -> ProjectRegistry:
    return request.app.state.registry  # type: ignore[no-any-return]


async def _resolve_project_path(
    project_id: str, registry: ProjectRegistry
) -> Path:
    """Return project_path or raise 404."""
    project = await registry.get(project_id)
    if project is None:
        raise HTTPException(status_code=404, detail=f"project {project_id!r} not found")
    return Path(project.path)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _load_flow(state_path: Path) -> dict[str, Any] | None:
    """Parse a flow state.json into a FlowSummary-compatible dict, or None on error."""
    try:
        raw = json.loads(state_path.read_text(encoding="utf-8"))
    except Exception:
        logger.warning("flows: skipping corrupt state.json: %s", state_path)
        return None

    try:
        steps = [
            {
                "id": s["id"],
                "soul": s.get("soul", ""),
                "task": s["task"],
                "deps": s.get("deps", []),
                "status": s.get("status", "pending"),
                "approval": bool(s.get("approval", False)),
                "on_fail": s.get("on_fail", "abort"),
                "run_id": s.get("run_id"),
                "type": s.get("type", "agent"),
                "output": s.get("output"),
            }
            for s in raw.get("steps", [])
        ]
        return {
            "flow_id": raw["flow_id"],
            "goal": raw["goal"],
            "status": raw["status"],
            "created": raw["created"],
            "steps": steps,
        }
    except (KeyError, TypeError):
        logger.warning("flows: missing required field in %s", state_path)
        return None


def _step_def_unchanged(prev: dict[str, Any], s: FlowStepInput) -> bool:
    """True if a step's definition (task/soul/deps) is identical to the prior one.

    deps are compared as sets — the editor derives deps from edges, so order may
    differ without a semantic change.
    """
    return (
        prev.get("task") == s.task
        and prev.get("soul", "") == s.soul
        and set(prev.get("deps", [])) == set(s.deps)
    )


def _preserved_step_ids(
    steps: list[FlowStepInput],
    prev_by_id: dict[str, dict[str, Any]],
) -> set[str]:
    """IDs whose prior run state (status/run_id/output) may be inherited on update.

    A step is invalidated (NOT preserved) if it is new, its definition changed, or
    it transitively depends on an invalidated step — n8n-style downstream cache
    invalidation, so a preserved step's output is always still valid (its upstreams
    are unchanged too).
    """
    invalid: set[str] = set()
    for s in steps:
        prev = prev_by_id.get(s.id)
        if prev is None or not _step_def_unchanged(prev, s):
            invalid.add(s.id)

    # Forward adjacency: dep -> [dependents].
    adjacency: dict[str, list[str]] = {s.id: [] for s in steps}
    for s in steps:
        for dep in s.deps:
            if dep in adjacency:
                adjacency[dep].append(s.id)

    # BFS: propagate invalidation to all transitive dependents.
    queue = list(invalid)
    while queue:
        node = queue.pop(0)
        for dependent in adjacency.get(node, []):
            if dependent not in invalid:
                invalid.add(dependent)
                queue.append(dependent)

    return {s.id for s in steps} - invalid


def _build_state_json(
    flow_id: str,
    req: FlowWriteRequest,
    created: str,
    prev_by_id: dict[str, dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Build the state.json dict from a FlowWriteRequest.

    On update (prev_by_id provided), steps whose definition is unchanged AND whose
    upstreams are unchanged inherit prior status/run_id/output so execution results
    survive edits. Fresh writes (POST) reset every step to pending.
    """
    prev_by_id = prev_by_id or {}
    preserved = _preserved_step_ids(req.steps, prev_by_id) if prev_by_id else set()

    steps: list[dict[str, Any]] = []
    for s in req.steps:
        step: dict[str, Any] = {
            "id": s.id,
            "soul": s.soul,
            "task": s.task,
            "deps": s.deps,
            "retry": s.retry,
            "approval": s.approval,
            "on_fail": s.on_fail,
            "type": s.type,
            "status": "pending",
        }
        if s.id in preserved:
            prev = prev_by_id[s.id]
            step["status"] = prev.get("status", "pending")
            if prev.get("run_id") is not None:
                step["run_id"] = prev["run_id"]
            if prev.get("output") is not None:
                step["output"] = prev["output"]
        steps.append(step)

    return {
        "flow_id": flow_id,
        "goal": req.goal,
        "created": created,
        "status": "pending",
        "steps": steps,
    }


def _write_state_atomic(state_path: Path, data: dict[str, Any]) -> None:
    """Write state.json atomically via tmp + os.replace."""
    tmp = state_path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    os.replace(tmp, state_path)


async def _validate_with_forge(state_path: Path, project_path: Path) -> str | None:
    """Run forge.sh flow validate <flow_id> against the written state.json.

    Returns None on success, or an error string (stderr) on failure.
    Falls back gracefully when forge.sh is unavailable or the project has no
    .golem directory (e.g. in unit tests with a bare tmp_path).
    """
    if not FORGE_SH_PATH.is_file():
        return None  # forge.sh absent — skip external validation in tests

    # Skip forge validation if the project lacks a .golem directory — forge.sh
    # requires an initialized GolemGarden project and will exit rc=1 otherwise.
    if not (project_path / ".golem").is_dir():
        return None

    # flow_id is the directory name (parent of state.json).
    flow_id = state_path.parent.name
    env = {k: v for k, v in os.environ.items() if k in {
        "PATH", "HOME", "USERPROFILE", "USER", "USERNAME",
        "SHELL", "TERM", "COMSPEC", "LANG", "LC_ALL", "LC_CTYPE", "TZ",
        "TEMP", "TMP", "TMPDIR",
        "MSYSTEM", "MSYS_NO_PATHCONV", "MSYS2_ARG_CONV_EXCL",
        "GOLEM_PROJECT", "GOLEM_FORGE_SH", "GOLEM_FORGE_SH_BASH",
        "GOLEM_EXTRA_PROJECT_ROOTS",
    }}
    env["GOLEM_PROJECT"] = to_bash_path(project_path)
    env["MSYS_NO_PATHCONV"] = "1"
    env["MSYS2_ARG_CONV_EXCL"] = "*"

    try:
        proc = await asyncio.create_subprocess_exec(
            BASH_BIN,
            FORGE_SH_BASH_PATH,
            "flow",
            "validate",
            flow_id,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            stdin=asyncio.subprocess.DEVNULL,
            cwd=str(project_path),
            env=env,
        )
        try:
            stdout_b, stderr_b = await asyncio.wait_for(proc.communicate(), timeout=30.0)
        except asyncio.TimeoutError:
            proc.kill()
            await proc.wait()
            return "forge flow validate timed out"

        if proc.returncode != 0:
            stderr_text = stderr_b.decode("utf-8", errors="replace").strip()
            return stderr_text or f"forge validate exited rc={proc.returncode}"
        return None
    except (OSError, FileNotFoundError) as exc:
        logger.warning("flows: forge validate subprocess failed: %s", exc)
        return None  # Cannot run — skip external validation


def _python_cycle_check(steps: list[FlowStepInput]) -> str | None:
    """Pure-Python Kahn cycle detection for the step graph.

    Returns None if acyclic, or an error message if a cycle is found.
    Used when forge.sh is unavailable.
    """
    id_set = {s.id for s in steps}
    in_degree: dict[str, int] = {s.id: 0 for s in steps}
    adjacency: dict[str, list[str]] = {s.id: [] for s in steps}

    for step in steps:
        for dep in step.deps:
            if dep in id_set:
                in_degree[step.id] += 1
                adjacency[dep].append(step.id)

    queue = [sid for sid, deg in in_degree.items() if deg == 0]
    visited = 0
    while queue:
        node = queue.pop(0)
        visited += 1
        for neighbor in adjacency[node]:
            in_degree[neighbor] -= 1
            if in_degree[neighbor] == 0:
                queue.append(neighbor)

    if visited < len(steps):
        cycle_nodes = [sid for sid, deg in in_degree.items() if deg > 0]
        return f"cycle detected in steps: {cycle_nodes}"
    return None


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------


@router.get("/flows", response_model=list[FlowSummary])
async def list_flows(
    project_id: str,
    limit: int = Query(default=20, ge=1, le=100),
    registry: ProjectRegistry = Depends(_get_registry),
) -> list[FlowSummary]:
    """List flows sorted by directory mtime descending (newest first)."""
    project_path = await _resolve_project_path(project_id, registry)
    flows_dir = project_path / ".golem" / "flows"

    if not flows_dir.is_dir():
        return []

    entries: list[tuple[float, Path]] = []
    for entry in flows_dir.iterdir():
        if not entry.is_dir():
            continue
        if not _FLOW_DIR_RE.match(entry.name):
            continue
        state_path = entry / "state.json"
        if not state_path.is_file():
            continue
        entries.append((entry.stat().st_mtime, state_path))

    # full sort 대신 상위 limit개만 추출 — 디렉토리가 커져도 O(n log limit)
    top_entries = heapq.nlargest(limit, entries, key=lambda x: x[0])

    results: list[FlowSummary] = []
    for _, state_path in top_entries:
        if len(results) >= limit:
            break
        data = _load_flow(state_path)
        if data is None:
            continue
        try:
            results.append(FlowSummary(**data))
        except Exception:
            logger.warning("flows: model validation failed for %s", state_path)

    return results


@router.post("/flows", status_code=201)
async def create_flow(
    project_id: str,
    body: FlowWriteRequest,
    registry: ProjectRegistry = Depends(_get_registry),
) -> dict[str, str]:
    """Create a new flow and persist state.json.

    Runs forge.sh flow validate to detect DAG cycles before returning.
    Returns 400 if validation fails; 404 if project not found.
    """
    project_path = await _resolve_project_path(project_id, registry)

    # Pure-Python cycle check (fast, always runs even without forge.sh).
    cycle_err = _python_cycle_check(body.steps)
    if cycle_err:
        raise HTTPException(status_code=400, detail=cycle_err)

    flow_id = str(uuid.uuid4())
    flow_dir = project_path / ".golem" / "flows" / flow_id
    state_path = flow_dir / "state.json"
    created = datetime.now(tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    flow_dir.mkdir(parents=True, exist_ok=True)
    try:
        data = _build_state_json(flow_id, body, created)
        _write_state_atomic(state_path, data)

        # forge.sh flow validate — defense-in-depth, NON-fatal. The authoritative
        # guards are Pydantic (fields/deps) + _python_cycle_check (DAG), which are
        # equivalent to flow_validate and env-independent. The subprocess path is
        # fragile across bash flavors (Git Bash /c/ vs WSL /mnt/c/ from
        # to_bash_path), so its failure is logged, not surfaced as 400.
        err = await _validate_with_forge(state_path, project_path)
        if err:
            logger.warning("flows: forge validate advisory failure for %s: %s", flow_id, err)
    except HTTPException:
        raise
    except Exception as exc:
        shutil.rmtree(flow_dir, ignore_errors=True)
        logger.exception("flows: unexpected error creating flow: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    return {"flow_id": flow_id}


@router.put("/flows/{flow_id}")
async def update_flow(
    project_id: str,
    flow_id: str,
    body: FlowWriteRequest,
    registry: ProjectRegistry = Depends(_get_registry),
) -> dict[str, str]:
    """Update an existing flow's state.json, resetting status to pending.

    Returns 404 if flow or project not found; 400 on DAG validation failure.
    """
    if not _FLOW_DIR_RE.match(flow_id):
        raise HTTPException(status_code=400, detail=f"invalid flow_id: {flow_id!r}")

    project_path = await _resolve_project_path(project_id, registry)
    flow_dir = project_path / ".golem" / "flows" / flow_id
    if not flow_dir.is_dir():
        raise HTTPException(status_code=404, detail=f"flow {flow_id!r} not found")

    # Pure-Python cycle check.
    cycle_err = _python_cycle_check(body.steps)
    if cycle_err:
        raise HTTPException(status_code=400, detail=cycle_err)

    state_path = flow_dir / "state.json"

    # Preserve original created timestamp + prior per-step run state (status/run_id/
    # output) so editing a flow doesn't wipe execution results.
    created = datetime.now(tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    prev_by_id: dict[str, Any] = {}
    if state_path.is_file():
        try:
            old = json.loads(state_path.read_text(encoding="utf-8"))
            created = old.get("created", created)
            prev_by_id = {
                s["id"]: s for s in old.get("steps", []) if isinstance(s, dict) and "id" in s
            }
        except Exception:
            pass

    data = _build_state_json(flow_id, body, created, prev_by_id)
    _write_state_atomic(state_path, data)

    # NON-fatal advisory (see create_flow) — Python guards are authoritative.
    err = await _validate_with_forge(state_path, project_path)
    if err:
        logger.warning("flows: forge validate advisory failure for %s: %s", flow_id, err)

    return {"flow_id": flow_id}


@router.delete("/flows/{flow_id}", status_code=204)
async def delete_flow(
    project_id: str,
    flow_id: str,
    registry: ProjectRegistry = Depends(_get_registry),
) -> None:
    """Delete a flow directory entirely.

    Returns 404 if the flow does not exist; 204 on success.
    """
    if not _FLOW_DIR_RE.match(flow_id):
        raise HTTPException(status_code=400, detail=f"invalid flow_id: {flow_id!r}")

    project_path = await _resolve_project_path(project_id, registry)
    flow_dir = project_path / ".golem" / "flows" / flow_id
    if not flow_dir.is_dir():
        raise HTTPException(status_code=404, detail=f"flow {flow_id!r} not found")

    shutil.rmtree(flow_dir)
