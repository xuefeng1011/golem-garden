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
import time
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel, field_validator, model_validator

from golem_gateway.config import (
    BASH_BIN,
    FORGE_SH_BASH_PATH,
    FORGE_SH_PATH,
    RUN_LOCK_STALE_SECONDS,
    STATE_LOCK_STALE_SECONDS,
    STATE_LOCK_TIMEOUT_SECONDS,
    build_forge_subprocess_env,
    redact_stderr,
)
from golem_gateway.forge_runner import ForgeRunner
from golem_gateway.registry import ProjectRegistry

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1/projects/{project_id}", tags=["flows"])

# Safe flow directory name: uuid or flow_<epoch>_<pid> fallback (lib/flow-dag.sh).
_FLOW_DIR_RE = re.compile(r"^(flow_[A-Za-z0-9_]+|[0-9a-f-]{36})$", re.IGNORECASE)

# Valid on_fail values pattern.
_ON_FAIL_RE = re.compile(r"^(abort|continue|goto:[A-Za-z0-9_-]+)$")

# Valid step id pattern.
_STEP_ID_RE = re.compile(r"^[A-Za-z0-9_-]+$")

# Mirrors lib/flow-contract.sh's `sed 's/},[[:space:]]*{/}\n{/g'` step splitter —
# a literal `},{` (optionally with whitespace after the comma) in a task value
# breaks the bash parser's 1-depth step-object boundary detection. Do not widen
# this regex; it must stay an exact mirror of the bash-side separator.
_BRACE_SPLIT_RE = re.compile(r"\},\s*\{")

# rubric item-split boundary in the bash extractor (_fc_get_rubric): items are
# split on a literal `","` (quote-comma-quote) sequence, so that sequence is
# forbidden inside an item. `[`/`]` are forbidden separately because the bash
# array-extraction regex `"rubric":\[[^]]*\]` terminates early on the first `]`.
_RUBRIC_ITEM_MAX_LEN = 200
_RUBRIC_MAX_ITEMS = 4


# ---------------------------------------------------------------------------
# Models — read (response)
# ---------------------------------------------------------------------------


class FlowStep(BaseModel):
    id: str
    soul: str
    task: str
    deps: list[str]
    status: str
    retry: int = 1
    approval: bool = False
    on_fail: str = "abort"
    rubric: list[str] = []
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
    rubric: list[str] = []
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
        if _BRACE_SPLIT_RE.search(v):
            raise ValueError(
                "task must not contain a literal '},{' sequence "
                "(1-depth flow contract — breaks the bash steps parser)"
            )
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

    @field_validator("rubric")
    @classmethod
    def validate_rubric(cls, v: list[str]) -> list[str]:
        if len(v) > _RUBRIC_MAX_ITEMS:
            raise ValueError(
                f"rubric must contain at most {_RUBRIC_MAX_ITEMS} items"
            )
        for item in v:
            if not item.strip():
                raise ValueError("rubric items must not be empty")
            if len(item) > _RUBRIC_ITEM_MAX_LEN:
                raise ValueError(
                    f"rubric item exceeds {_RUBRIC_ITEM_MAX_LEN} characters"
                )
            if _BRACE_SPLIT_RE.search(item):
                raise ValueError(
                    "rubric item must not contain a literal '},{' sequence "
                    "(1-depth flow contract — breaks the bash steps parser)"
                )
            if "[" in item or "]" in item:
                raise ValueError(
                    "rubric item must not contain '[' or ']' "
                    "(breaks the bash rubric array extractor)"
                )
            if '","' in item:
                raise ValueError(
                    'rubric item must not contain a literal \'","\' sequence '
                    "(bash rubric item-split boundary)"
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
        # goto target reference check.
        for step in self.steps:
            if step.on_fail.startswith("goto:"):
                target = step.on_fail[5:]
                if target not in id_set:
                    raise ValueError(
                        f"step {step.id!r} on_fail goto references unknown id {target!r}"
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


def _load_flow(
    state_path: Path, *, include_output: bool = True
) -> dict[str, Any] | None:
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
                "retry": s.get("retry", 1),
                "approval": bool(s.get("approval", False)),
                "on_fail": s.get("on_fail", "abort"),
                "rubric": s.get("rubric", []),
                "run_id": s.get("run_id"),
                "type": s.get("type", "agent"),
                "output": s.get("output") if include_output else None,
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
    """True if a step's definition (task/soul/deps/type/rubric) is identical to the prior one.

    deps are compared as sets — the editor derives deps from edges, so order may
    differ without a semantic change. retry/on_fail/approval are not compared —
    they don't affect a step's produced output, so cache preservation ignores
    them. type IS compared: switching agent<->input changes execution semantics,
    so a cached result under the old type is invalid. rubric IS compared (order
    matters — item order is the verify [ITEM-k] numbering): it changes the
    executing SOUL's injected grading contract (B-5), so a cached result graded
    under a different rubric is invalid. Absent key normalizes to `[]` so old
    records (pre-B-5, no rubric key) compare equal to an explicit empty list.
    """
    return (
        prev.get("task") == s.task
        and prev.get("soul", "") == s.soul
        and set(prev.get("deps", [])) == set(s.deps)
        and prev.get("type", "agent") == s.type
        and prev.get("rubric", []) == s.rubric
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
            "rubric": s.rubric,
            "type": s.type,
            "status": "pending",
        }
        # 완료(done)된 단계만 결과를 승계한다. running/waiting_approval/failed 를
        # 그대로 보존하면 재실행 시 그 단계가 ready(pending|approved)도 done 도 아니어서
        # flow_next_ready 가 영영 선택하지 못하고 하류 deps 도 충족 안 돼 플로우가
        # 영구 정지한다(무한 'running' 재발 방지 — 코드리뷰 HIGH).
        if s.id in preserved and prev_by_id[s.id].get("status") == "done":
            prev = prev_by_id[s.id]
            step["status"] = "done"
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


def _flow_run_active(
    flow_dir: Path, project_id: str, flow_id: str, runner: ForgeRunner | None
) -> bool:
    """True if a `flow run <flow_id>` is currently executing for this project.

    Two independent execution paths can drive the same flow: the Gateway's own
    ForgeRunner (in-process) and a bash CLI invocation elsewhere on the machine
    (which holds lib/flow.sh's run.lock directory). A crashed run can leave
    state.json's status stuck at "running" forever with no live process behind
    it, so that field alone is never trusted here (HIGH-2).
    """
    if runner is not None and runner.find_active_flow_run(project_id, flow_id) is not None:
        return True

    run_lock_dir = flow_dir / "run.lock"
    if run_lock_dir.is_dir():
        try:
            age = time.time() - run_lock_dir.stat().st_mtime
        except OSError:
            return False  # vanished between is_dir() and stat() — treat as gone
        if age < RUN_LOCK_STALE_SECONDS:
            return True

    return False


@contextmanager
def _state_write_lock(state_path: Path) -> Iterator[None]:
    """Mirror lib/flow-dag.sh's mkdir-based state.json.lock protocol.

    mkdir is POSIX-atomic (no flock — unavailable on Git Bash), so the same
    lock directory doubles as the mutual-exclusion primitive shared with the
    bash CLI. The bash side reclaims stale locks via `kill -0 <holder-pid>`;
    Python cannot reliably kill -0 a bash-spawned pid on Windows, so staleness
    here is judged purely by the lock directory's mtime age
    (STATE_LOCK_STALE_SECONDS) rather than liveness.
    """
    lock_dir = state_path.parent / "state.json.lock"
    # time.monotonic() below measures elapsed wait (immune to wall-clock jumps);
    # time.time() is used only where a value is compared against st_mtime
    # (also wall-clock), both here and in _flow_run_active above. Do not swap
    # the two clocks between these uses.
    deadline = time.monotonic() + STATE_LOCK_TIMEOUT_SECONDS
    reclaimed = False
    while True:
        try:
            os.mkdir(lock_dir)
            break
        except FileExistsError:
            if not reclaimed:
                try:
                    age = time.time() - lock_dir.stat().st_mtime
                except OSError:
                    age = STATE_LOCK_STALE_SECONDS + 1.0
                if age > STATE_LOCK_STALE_SECONDS:
                    shutil.rmtree(lock_dir, ignore_errors=True)
                    reclaimed = True
                    continue
            if time.monotonic() >= deadline:
                raise HTTPException(
                    status_code=409,
                    detail="flow state is locked by another writer",
                )
            time.sleep(0.1)

    try:
        try:
            (lock_dir / "pid").write_text(str(os.getpid()), encoding="utf-8")
        except OSError as exc:
            logger.warning("flows: failed to write lock pid file %s: %s", lock_dir, exc)
        yield
    finally:
        shutil.rmtree(lock_dir, ignore_errors=True)


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
    env = build_forge_subprocess_env(project_path)

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
            if not stderr_text:
                return f"forge validate exited rc={proc.returncode}"
            # Full text server-side only (may contain absolute paths); the
            # returned string (surfaced only in a warning log at the call
            # site — this is an advisory check, never a raised error) is
            # redacted so no caller can accidentally leak it further.
            logger.error(
                "forge flow validate failed (rc=%s) for %s: %s",
                proc.returncode,
                state_path,
                stderr_text,
            )
            return redact_stderr(stderr_text)
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
        data = _load_flow(state_path, include_output=False)
        if data is None:
            continue
        try:
            results.append(FlowSummary(**data))
        except Exception:
            logger.warning("flows: model validation failed for %s", state_path)

    return results


@router.get("/flows/{flow_id}", response_model=FlowSummary)
async def get_flow(
    project_id: str,
    flow_id: str,
    registry: ProjectRegistry = Depends(_get_registry),
) -> FlowSummary:
    """Fetch a single flow by id.

    실행 중 폴링 전용 — 목록 전체(최대 20개 state.json 파싱)를 1.5초마다
    읽던 O(플로우 수) 디스크 부하를 O(1) 로 줄인다 (P4-1).
    """
    if not _FLOW_DIR_RE.match(flow_id):
        raise HTTPException(status_code=400, detail="invalid flow id")

    project_path = await _resolve_project_path(project_id, registry)
    state_path = project_path / ".golem" / "flows" / flow_id / "state.json"
    if not state_path.is_file():
        raise HTTPException(status_code=404, detail=f"flow {flow_id!r} not found")

    data = _load_flow(state_path)
    if data is None:
        raise HTTPException(status_code=500, detail="flow state.json is corrupt")
    return FlowSummary(**data)


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
    request: Request,
    registry: ProjectRegistry = Depends(_get_registry),
) -> dict[str, str]:
    """Update an existing flow's state.json, resetting status to pending.

    Returns 404 if flow or project not found; 400 on DAG validation failure;
    409 if the flow currently has an active run, or its state.json is locked
    by another writer (HIGH-2).
    """
    if not _FLOW_DIR_RE.match(flow_id):
        raise HTTPException(status_code=400, detail=f"invalid flow_id: {flow_id!r}")

    project_path = await _resolve_project_path(project_id, registry)
    flow_dir = project_path / ".golem" / "flows" / flow_id
    if not flow_dir.is_dir():
        raise HTTPException(status_code=404, detail=f"flow {flow_id!r} not found")

    runner: ForgeRunner | None = getattr(request.app.state, "forge_runner", None)
    if _flow_run_active(flow_dir, project_id, flow_id, runner):
        raise HTTPException(status_code=409, detail="cannot edit a running flow")

    # Pure-Python cycle check.
    cycle_err = _python_cycle_check(body.steps)
    if cycle_err:
        raise HTTPException(status_code=400, detail=cycle_err)

    state_path = flow_dir / "state.json"

    with _state_write_lock(state_path):
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
    request: Request,
    registry: ProjectRegistry = Depends(_get_registry),
) -> None:
    """Delete a flow directory entirely.

    Returns 404 if the flow does not exist; 409 if it has an active run or its
    state.json is locked by another writer (HIGH-2); 204 on success.
    """
    if not _FLOW_DIR_RE.match(flow_id):
        raise HTTPException(status_code=400, detail=f"invalid flow_id: {flow_id!r}")

    project_path = await _resolve_project_path(project_id, registry)
    flow_dir = project_path / ".golem" / "flows" / flow_id
    if not flow_dir.is_dir():
        raise HTTPException(status_code=404, detail=f"flow {flow_id!r} not found")

    runner: ForgeRunner | None = getattr(request.app.state, "forge_runner", None)
    if _flow_run_active(flow_dir, project_id, flow_id, runner):
        raise HTTPException(status_code=409, detail="cannot delete a running flow")

    state_path = flow_dir / "state.json"
    with _state_write_lock(state_path):
        shutil.rmtree(flow_dir)
