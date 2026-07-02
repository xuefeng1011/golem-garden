"""growth_log.py — append chat-run outcomes to .golem/growth-log/{soul_id}.jsonl

Schema matches lib/growth-log.sh growth_log_append() exactly so that the
rank-up / achievement / chemistry pipeline treats chat runs identically to
forge.sh runs.

Minimal required fields:
  date, task, result, files_changed, tests_passed

Optional cost-tracking fields (emitted only when tokens_in > 0):
  tokens_in, tokens_out, tokens_cache, cost_usd, model, duration_ms

All failures are swallowed with a log warning — the chat run must not be
blocked by a bookkeeping error.
"""

from __future__ import annotations

import json
import logging
from datetime import date
from pathlib import Path

logger = logging.getLogger(__name__)


def append_entry(
    project_root: Path,
    soul_id: str,
    task: str,
    result: str,
    *,
    files: int = 0,
    tests: int = 0,
    model: str = "",
    tokens_in: int = 0,
    tokens_out: int = 0,
    tokens_cache: int = 0,
    cost_usd: float = 0.0,
    duration_ms: int = 0,
) -> bool:
    """Append one JSONL entry to .golem/growth-log/{soul_id}.jsonl.

    Returns True on success, False on any failure (exception is logged and
    swallowed — callers must not crash on a bookkeeping error).

    Parameters mirror growth_log_append() in lib/growth-log.sh:
      - result:  "success" | "fail"
      - task:    first 80 chars of the user message (newlines stripped)
      - files:   files_changed (0 for chat runs — no direct FS side-effects)
      - tests:   tests_passed  (0 unless the run explicitly ran tests)
    """
    try:
        growth_dir = project_root / ".golem" / "growth-log"
        growth_dir.mkdir(parents=True, exist_ok=True)

        log_file = growth_dir / f"{soul_id}.jsonl"

        today = date.today().isoformat()  # YYYY-MM-DD

        # Normalise task: strip newlines, trim to 80 chars to stay readable.
        task_clean = task.replace("\n", " ").replace("\r", "").strip()[:80]

        entry: dict = {
            "date": today,
            "task": task_clean,
            "result": result,
            "files_changed": files,
            "tests_passed": tests,
        }

        # Emit cost-tracking fields only when we have real token data,
        # mirroring the shell `if [ "$tokens_in" -gt 0 ]` guard.
        if tokens_in > 0:
            entry["tokens_in"] = tokens_in
            entry["tokens_out"] = tokens_out
            entry["tokens_cache"] = tokens_cache
            entry["cost_usd"] = round(cost_usd, 6)
            entry["model"] = model
            entry["duration_ms"] = duration_ms

        # 컴팩트 구분자 필수 — bash 파이프라인(rank/achievement/cost)은
        # `grep -o '"result":"success"'` 류로 파싱하므로 json.dumps 기본
        # 구분자(", ", ": ")로 쓰면 이 엔트리들이 조용히 누락된다
        # (실제 발생했던 드리프트 — tests/golden/growth-log.golden.jsonl 계약).
        line = json.dumps(entry, ensure_ascii=False, separators=(",", ":"))

        with log_file.open("a", encoding="utf-8") as fh:
            fh.write(line + "\n")

        logger.debug(
            "growth_log: appended entry for %s (%s) to %s", soul_id, result, log_file
        )
        return True

    except Exception:
        logger.warning(
            "growth_log: failed to append entry for soul_id=%r project=%s",
            soul_id,
            project_root,
            exc_info=True,
        )
        return False
