"""Cross-implementation contract: FlowWriteRequest ↔ lib/flow-contract.sh.

tests/golden/flow-cases/ 의 같은 케이스 파일을 bash 측
(tests/bats/test_flow.bats "골든 케이스")도 검증한다 — 두 검증기의 판정이
갈라지면 편집기(Pydantic)가 통과시킨 플로우를 엔진(bash)이 거부하거나
그 반대가 된다.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from pydantic import ValidationError

from golem_gateway.api_flows import FlowWriteRequest

CASES_DIR = (
    Path(__file__).resolve().parents[3] / "tests" / "golden" / "flow-cases"
)


def _cases() -> list[Path]:
    assert CASES_DIR.is_dir(), f"golden cases missing: {CASES_DIR}"
    return sorted(CASES_DIR.glob("*.json"))


@pytest.mark.parametrize("case_path", _cases(), ids=lambda p: p.name)
def test_pydantic_verdict_matches_filename(case_path: Path) -> None:
    data = json.loads(case_path.read_text(encoding="utf-8"))
    expect_valid = case_path.name.startswith("valid-")

    if expect_valid:
        FlowWriteRequest.model_validate(data)  # must not raise
    else:
        with pytest.raises(ValidationError):
            FlowWriteRequest.model_validate(data)
