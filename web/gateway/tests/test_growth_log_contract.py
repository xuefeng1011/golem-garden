"""Cross-implementation golden contract: growth_log.py ↔ lib/growth-log.sh.

같은 입력에 대해 두 작성자(bash/python)가 byte-동일한 JSONL 을 만들어야
bash 파이프라인(rank/achievement/cost — grep 기반)이 chat 런을 누락하지 않는다.
골든 파일은 tests/golden/growth-log.golden.jsonl 단일 소스 — bash 측은
tests/bats/test_growth_log.bats 의 동일 계약 케이스가 같은 파일을 검증한다.
"""

from __future__ import annotations

import re
from pathlib import Path

from golem_gateway.growth_log import append_entry

GOLDEN = (
    Path(__file__).resolve().parents[3] / "tests" / "golden" / "growth-log.golden.jsonl"
)

_DATE_RE = re.compile(r'"date":"\d{4}-\d{2}-\d{2}"')


def _normalize(line: str) -> str:
    return _DATE_RE.sub('"date":"DATE"', line.strip())


def test_python_writer_matches_golden(tmp_path: Path) -> None:
    assert GOLDEN.is_file(), f"golden fixture missing: {GOLDEN}"

    ok1 = append_entry(
        tmp_path, "goldy", '골든 "인용" 태스크 | 파이프', "success", files=2, tests=3
    )
    ok2 = append_entry(
        tmp_path,
        "goldy",
        "비용 추적 태스크",
        "success",
        model="sonnet",
        tokens_in=100,
        tokens_out=50,
        tokens_cache=20,
        cost_usd=0.123,
        duration_ms=1500,
    )
    assert ok1 and ok2

    written = (tmp_path / ".golem" / "growth-log" / "goldy.jsonl").read_text(
        encoding="utf-8"
    ).splitlines()
    golden = GOLDEN.read_text(encoding="utf-8").splitlines()

    assert [_normalize(x) for x in written] == [g.strip() for g in golden]


def test_no_spaced_separators(tmp_path: Path) -> None:
    """`": "` / `", "` 구분자 금지 — bash grep 파서가 매칭 실패하는 형태."""
    append_entry(tmp_path, "goldy", "compact check", "success")
    line = (tmp_path / ".golem" / "growth-log" / "goldy.jsonl").read_text(
        encoding="utf-8"
    )
    assert '": ' not in line
    assert '", ' not in line
