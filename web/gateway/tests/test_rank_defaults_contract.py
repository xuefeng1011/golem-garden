"""Cross-implementation golden contract: souls.py rank 기본값 ↔ soul-parser.sh.

souls.py 의 _RANK_DEFAULT_* 는 API 표시용, bash soul-parser.sh 는 실제 강제 —
두 소스가 어긋나면 UI 가 실제와 다른 권한을 표시한다. 골든 파일
tests/golden/rank-defaults.txt 가 단일 소스이며 bash 측은
tests/bats/test_soul_parser.bats 의 동일 계약 케이스가 같은 파일을 검증한다.
"""

from __future__ import annotations

from pathlib import Path

from golem_gateway.souls import (
    _RANK_DEFAULT_ISOLATION,
    _RANK_DEFAULT_MAX_TURNS,
    _RANK_DEFAULT_TOOLS,
)

GOLDEN = (
    Path(__file__).resolve().parents[3] / "tests" / "golden" / "rank-defaults.txt"
)


def _golden_rows() -> list[tuple[str, list[str], int, str]]:
    rows = []
    for line in GOLDEN.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        rank, tools, turns, isolation = line.split("|")
        rows.append((rank, [t.strip() for t in tools.split(",")], int(turns), isolation))
    return rows


def test_rank_defaults_match_golden() -> None:
    assert GOLDEN.is_file(), f"golden fixture missing: {GOLDEN}"
    rows = _golden_rows()
    assert len(rows) == 5, "골든은 5개 랭크 전부를 정의해야 한다"

    for rank, tools, turns, isolation in rows:
        assert _RANK_DEFAULT_TOOLS.get(rank) == tools, f"tools 불일치: {rank}"
        assert _RANK_DEFAULT_MAX_TURNS.get(rank) == turns, f"maxTurns 불일치: {rank}"
        # isolation 은 dict 에 novice/junior 만 명시, 나머지는 .get 기본값 worktree
        assert _RANK_DEFAULT_ISOLATION.get(rank, "worktree") == isolation, (
            f"isolation 불일치: {rank}"
        )
