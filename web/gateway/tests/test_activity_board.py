from __future__ import annotations

from pathlib import Path

import pytest

from golem_gateway.activity import _strip_inline_emphasis, build_board


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("**Ryn**", "Ryn"),
        ("**junior**", "junior"),
        ("plain", "plain"),
        ("", ""),
        ("**", "**"),
        ("**unclosed", "**unclosed"),
        ("mixed **bold** text", "mixed bold text"),
        ("***bolditalic***", "*bolditalic*"),
        # snake_case identifiers must survive untouched
        ("code_reviewer", "code_reviewer"),
        ("claude_3_5_sonnet", "claude_3_5_sonnet"),
        ("snake_case_name", "snake_case_name"),
        ("test-engineer", "test-engineer"),
        # single-asterisk italic is intentionally not stripped
        ("*italic*", "*italic*"),
    ],
)
def test_strip_inline_emphasis(raw: str, expected: str) -> None:
    assert _strip_inline_emphasis(raw) == expected


def _write_board(tmp_path: Path, body: str) -> Path:
    golem = tmp_path / ".golem"
    golem.mkdir()
    (golem / "forge-board.md").write_text(body, encoding="utf-8")
    return tmp_path


def test_build_board_strips_bold_in_team_cells(tmp_path: Path) -> None:
    project = _write_board(
        tmp_path,
        "## 팀 구성\n\n"
        "| SOUL | 역할 | OMC Agent | 모델 | Rank | 상태 |\n"
        "|------|------|-----------|------|------|------|\n"
        "| **Ryn** | Backend | executor | sonnet | **junior** | active |\n"
        "| **Kai** | Frontend | executor | sonnet | novice | active |\n",
    )
    board = build_board(project)
    assert [m.name for m in board.team] == ["Ryn", "Kai"]
    assert [m.rank for m in board.team] == ["junior", "novice"]
    assert board.team[0].agent == "executor"
    assert board.team[0].status == "active"


def test_build_board_preserves_snake_case_identifiers(tmp_path: Path) -> None:
    project = _write_board(
        tmp_path,
        "## 팀 구성\n\n"
        "| SOUL | 역할 | OMC Agent | 모델 | Rank | 상태 |\n"
        "|------|------|-----------|------|------|------|\n"
        "| **Sage** | Auditor | code_reviewer | claude_3_5_sonnet | senior | standby |\n",
    )
    board = build_board(project)
    member = board.team[0]
    assert member.agent == "code_reviewer"
    assert member.model == "claude_3_5_sonnet"


def test_build_board_missing_file_returns_empty(tmp_path: Path) -> None:
    board = build_board(tmp_path)
    assert board.team == []
    assert board.tech_debt == []
    assert board.history == []
    assert board.raw_md == ""
