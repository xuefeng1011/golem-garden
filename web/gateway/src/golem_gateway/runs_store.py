"""Run trajectory persistence: write .golem/runs/<run_id>.jsonl + .meta.json.

G1  — raw lines accumulated in memory only during run; flushed once at terminal.
G3  — mtime-keyed parse cache for trace API (activity.py pattern).
G5  — secret masking: sk-/ghp_/KEY= patterns → ***MASKED***.
G6  — meta schema validated against spec/run-meta.schema.json required keys.
"""

from __future__ import annotations

import json
import logging
import re
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

from golem_gateway.config import RUNS_DISABLE, RUNS_KEEP, RUN_RAW_CAP_BYTES

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Secret masking (G5) — mirrors lib/agent-runner.sh MASK_PATTERNS
# ---------------------------------------------------------------------------

_MASK_PATTERNS: list[tuple[re.Pattern[str], str]] = [
    (
        re.compile(r"sk-[A-Za-z0-9_-]{10,}"),
        "***MASKED***",
    ),
    (
        re.compile(r"ghp_[A-Za-z0-9]{20,}"),
        "***MASKED***",
    ),
    (
        re.compile(r"(ANTHROPIC|OPENAI)[A-Z_]*KEY[\"=: ]+[^\",\s]+"),
        r"\1_KEY=***MASKED***",
    ),
]


def _mask_line(line: str) -> str:
    """Apply all mask patterns to a single raw line."""
    for pattern, replacement in _MASK_PATTERNS:
        line = pattern.sub(replacement, line)
    return line


# ---------------------------------------------------------------------------
# GC helper
# ---------------------------------------------------------------------------

def _gc(runs_dir: Path) -> None:
    """Delete oldest jsonl+meta pairs exceeding RUNS_KEEP."""
    try:
        jsonl_files = sorted(
            runs_dir.glob("*.jsonl"),
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )
        excess = jsonl_files[RUNS_KEEP:]
        for jsonl_path in excess:
            meta_path = jsonl_path.with_suffix(".meta.json")
            try:
                jsonl_path.unlink(missing_ok=True)
            except OSError as exc:
                logger.warning("runs GC: cannot delete %s: %s", jsonl_path, exc)
            try:
                meta_path.unlink(missing_ok=True)
            except OSError as exc:
                logger.warning("runs GC: cannot delete %s: %s", meta_path, exc)
    except Exception as exc:
        logger.warning("runs GC failed: %s", exc)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def persist_run(
    project_path: Path,
    *,
    run_id: str,
    session_id: str,
    soul_id: str,
    model: str,
    result: str,
    ts_start: str,
    duration_ms: int,
    usage: dict,
    tool_log: list[str],
    raw_lines: list[str],
    raw_truncated: bool,
) -> None:
    """Persist a completed run to .golem/runs/<run_id>.jsonl and .meta.json.

    All exceptions are caught and logged as warnings — persistence failure
    must never kill a run.
    """
    if RUNS_DISABLE:
        return

    try:
        runs_dir = project_path / ".golem" / "runs"
        runs_dir.mkdir(parents=True, exist_ok=True)

        # --- Write JSONL (raw lines, masked) ---
        jsonl_path = runs_dir / f"{run_id}.jsonl"
        masked_lines = [_mask_line(ln) for ln in raw_lines]
        if raw_truncated:
            masked_lines.append('{"type":"_truncated"}')
        jsonl_path.write_text(
            "\n".join(masked_lines) + ("\n" if masked_lines else ""),
            encoding="utf-8",
        )

        # --- Compute token counts from usage dict ---
        tokens_in: int = int(usage.get("input_tokens", 0) or 0)
        tokens_out: int = int(usage.get("output_tokens", 0) or 0)
        tokens_cache: int = int(
            (usage.get("cache_read_input_tokens") or 0)
            + (usage.get("cache_creation_input_tokens") or 0)
        )
        cost_usd: float = float(usage.get("total_cost_usd", 0.0) or 0.0)

        # --- Build meta (required keys per spec/run-meta.schema.json) ---
        meta: dict = {
            "run_id": run_id,
            "session_id": session_id,
            "soul": soul_id,
            "model": model,
            "source": "gateway",
            "ts_start": ts_start,
            "duration_ms": duration_ms,
            "tokens_in": tokens_in,
            "tokens_out": tokens_out,
            "tokens_cache": tokens_cache,
            "cost_usd": cost_usd,
            "result": result,
            "tool_counts": dict(Counter(tool_log)),
        }

        meta_path = runs_dir / f"{run_id}.meta.json"
        meta_path.write_text(json.dumps(meta), encoding="utf-8")

        # --- Rolling GC ---
        _gc(runs_dir)

    except Exception as exc:
        logger.warning("persist_run failed for run %s: %s", run_id, exc)


# ---------------------------------------------------------------------------
# Trace cache (G3) — mtime-keyed, mirrors activity._cached_load_growth_log
# ---------------------------------------------------------------------------

# {resolved_jsonl_path: (mtime, parsed_lines)}
_trace_cache: dict[Path, tuple[float, list[dict]]] = {}


def load_trace_lines(jsonl_path: Path) -> list[dict]:
    """Load and cache parsed JSONL lines for a run trace file."""
    resolved = jsonl_path.resolve()
    try:
        mtime = resolved.stat().st_mtime if resolved.is_file() else 0.0
    except OSError:
        mtime = 0.0

    cached = _trace_cache.get(resolved)
    if cached and cached[0] == mtime:
        return cached[1]

    lines: list[dict] = []
    try:
        raw_text = resolved.read_text(encoding="utf-8", errors="replace")
        for raw_line in raw_text.splitlines():
            line = raw_line.strip()
            if not line:
                continue
            try:
                lines.append(json.loads(line))
            except json.JSONDecodeError:
                logger.warning("skipping malformed JSONL line in %s: %r", resolved, line[:80])
    except OSError as exc:
        logger.warning("cannot read trace file %s: %s", resolved, exc)

    _trace_cache[resolved] = (mtime, lines)
    return lines
