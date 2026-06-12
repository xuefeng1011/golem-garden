"""Observation console aggregation endpoint.

GET /v1/projects/{project_id}/console

Single aggregated response for the UI observation console (G10 — no
per-screen polling).  Combines active runs, run stats, per-soul breakdown,
recent run metas, and budget in one call.
"""

from __future__ import annotations

import time
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from golem_gateway.activity import BudgetResponse, build_budget
from golem_gateway.api_traces import RunMeta, _get_registry, _resolve_project_path
from golem_gateway.registry import ProjectRegistry
from golem_gateway.runs_store import load_all_metas
from golem_gateway.session_manager import SessionManager

router = APIRouter(prefix="/v1/projects/{project_id}", tags=["console"])

_RECENT_RUNS_LIMIT = 20


# ---------------------------------------------------------------------------
# Response models
# ---------------------------------------------------------------------------

class ActiveRunItem(BaseModel):
    run_id: str
    session_id: str
    soul: str
    elapsed_ms: int


class RunStats(BaseModel):
    total_runs: int
    success: int
    error: int
    timeout: int
    success_rate: float
    avg_duration_ms: int
    total_cost_usd: float
    total_tokens_out: int


class SoulStats(BaseModel):
    soul: str
    runs: int
    cost_usd: float
    success_rate: float


class ConsoleResponse(BaseModel):
    active_runs: list[ActiveRunItem]
    stats: RunStats
    by_soul: list[SoulStats]
    recent_runs: list[RunMeta]
    budget: BudgetResponse


# ---------------------------------------------------------------------------
# Dependency
# ---------------------------------------------------------------------------

def _get_manager(request: Request) -> SessionManager:
    return request.app.state.session_manager  # type: ignore[no-any-return]


# ---------------------------------------------------------------------------
# Route
# ---------------------------------------------------------------------------

@router.get("/console", response_model=ConsoleResponse)
async def get_console(
    project_id: str,
    registry: ProjectRegistry = Depends(_get_registry),
    manager: SessionManager = Depends(_get_manager),
) -> ConsoleResponse:
    """Return aggregated observation data for the console UI."""
    project_path = await _resolve_project_path(project_id, registry)

    # --- Active runs ---
    now = time.monotonic()
    active_run_items: list[ActiveRunItem] = [
        ActiveRunItem(
            run_id=run.run_id,
            session_id=run.session_id,
            soul=run.soul_id,
            elapsed_ms=int((now - run.started_at) * 1000),
        )
        for run in manager.active_runs_for(project_id)
    ]

    # --- Meta aggregation (up to 200, rolling window enforced by GC) ---
    runs_dir = project_path / ".golem" / "runs"
    all_metas = load_all_metas(runs_dir)

    total = len(all_metas)
    success_count = 0
    error_count = 0
    timeout_count = 0
    total_duration_ms = 0
    total_cost_usd = 0.0
    total_tokens_out = 0

    # per-soul accumulators
    soul_runs: dict[str, int] = {}
    soul_cost: dict[str, float] = {}
    soul_success: dict[str, int] = {}

    for meta in all_metas:
        result = str(meta.get("result") or "")
        if result == "success":
            success_count += 1
        elif result == "timeout":
            timeout_count += 1
        else:
            error_count += 1

        total_duration_ms += int(meta.get("duration_ms") or 0)
        cost = float(meta.get("cost_usd") or 0.0)
        total_cost_usd += cost
        total_tokens_out += int(meta.get("tokens_out") or 0)

        soul = str(meta.get("soul") or "")
        soul_runs[soul] = soul_runs.get(soul, 0) + 1
        soul_cost[soul] = soul_cost.get(soul, 0.0) + cost
        if result == "success":
            soul_success[soul] = soul_success.get(soul, 0) + 1

    success_rate = round(success_count / total, 4) if total else 0.0
    avg_duration_ms = (total_duration_ms // total) if total else 0

    stats = RunStats(
        total_runs=total,
        success=success_count,
        error=error_count,
        timeout=timeout_count,
        success_rate=success_rate,
        avg_duration_ms=avg_duration_ms,
        total_cost_usd=round(total_cost_usd, 6),
        total_tokens_out=total_tokens_out,
    )

    by_soul: list[SoulStats] = sorted(
        [
            SoulStats(
                soul=soul,
                runs=soul_runs[soul],
                cost_usd=round(soul_cost.get(soul, 0.0), 6),
                success_rate=round(soul_success.get(soul, 0) / soul_runs[soul], 4),
            )
            for soul in soul_runs
        ],
        key=lambda s: s.runs,
        reverse=True,
    )

    # --- Recent runs: newest 20, parsed as RunMeta ---
    recent_runs: list[RunMeta] = []
    for meta in all_metas[:_RECENT_RUNS_LIMIT]:
        try:
            recent_runs.append(RunMeta(**meta))
        except Exception:
            continue

    # --- Budget ---
    budget = build_budget(project_path)

    return ConsoleResponse(
        active_runs=active_run_items,
        stats=stats,
        by_soul=by_soul,
        recent_runs=recent_runs,
        budget=budget,
    )
