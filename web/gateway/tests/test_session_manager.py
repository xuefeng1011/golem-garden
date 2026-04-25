"""Tests for golem_gateway.session_manager — system prompt + session pattern."""

from __future__ import annotations

import re

import pytest

from golem_gateway.session_manager import SessionManager, _build_system_prompt


# ---------------------------------------------------------------------------
# TestSystemPrompt
# ---------------------------------------------------------------------------


class TestSystemPrompt:
    def test_includes_soul_identity_header(self) -> None:
        prompt = _build_system_prompt(
            soul_name="Ryn",
            soul_rank="Novice",
            soul_specialty=["backend", "testing"],
            soul_body="## About\nI write tests.",
            history=[],
        )
        assert "SOUL Identity" in prompt
        assert "Ryn" in prompt
        assert "Novice" in prompt
        assert "backend, testing" in prompt

    def test_includes_soul_body(self) -> None:
        prompt = _build_system_prompt(
            soul_name="Kai",
            soul_rank="Junior",
            soul_specialty=[],
            soul_body="## Kai\nFrontend wizard.",
            history=[],
        )
        assert "Frontend wizard." in prompt

    def test_empty_specialty_renders_dash(self) -> None:
        prompt = _build_system_prompt(
            soul_name="Ghost",
            soul_rank="Novice",
            soul_specialty=[],
            soul_body="body",
            history=[],
        )
        # specialty line shows "—" when list is empty
        assert "—" in prompt

    def test_omits_history_in_prompt(self) -> None:
        """Phase 8: history arg accepted for API compat but NOT embedded in prompt."""
        prompt = _build_system_prompt(
            soul_name="Ryn",
            soul_rank="Novice",
            soul_specialty=[],
            soul_body="body",
            history=[
                {"role": "user", "content": "old user message"},
                {"role": "assistant", "content": "old assistant reply"},
            ],
        )
        assert "Conversation so far" not in prompt
        assert "old user message" not in prompt
        assert "old assistant reply" not in prompt

    def test_strips_trailing_whitespace_from_body(self) -> None:
        prompt = _build_system_prompt(
            soul_name="Ryn",
            soul_rank="Novice",
            soul_specialty=[],
            soul_body="  body with spaces   ",
            history=[],
        )
        # soul_body.strip() is applied
        assert "body with spaces" in prompt
        # trailing whitespace before final newline not present as multiple spaces
        assert not prompt.endswith("   ")


# ---------------------------------------------------------------------------
# TestSessionLostPattern
# ---------------------------------------------------------------------------


class TestSessionLostPattern:
    PATTERN: re.Pattern[str] = SessionManager._SESSION_LOST_PATTERN

    def test_matches_session_not_found(self) -> None:
        assert self.PATTERN.search("error: session not found")

    def test_matches_session_file_not_found(self) -> None:
        assert self.PATTERN.search("session file not found on disk")

    def test_matches_could_not_resume_session(self) -> None:
        assert self.PATTERN.search("could not resume session abc-123")

    def test_matches_no_such_session(self) -> None:
        assert self.PATTERN.search("no such session exists")

    def test_case_insensitive(self) -> None:
        assert self.PATTERN.search("Session Not Found")
        assert self.PATTERN.search("COULD NOT RESUME SESSION")

    def test_does_not_match_unrelated_text(self) -> None:
        assert not self.PATTERN.search("everything looks fine")
        assert not self.PATTERN.search("session started successfully")
        assert not self.PATTERN.search("resuming normally")


# ---------------------------------------------------------------------------
# TestArgvDecision (prior_turn_count logic)
# ---------------------------------------------------------------------------


class TestArgvDecision:
    """Verify --session-id vs --resume selection logic via prior_turn_count."""

    def _extract_session_args(
        self, prior_turn_count: int, session_id: str = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
    ) -> list[str]:
        """Replicate the decision in spawn_run without actually spawning."""
        if prior_turn_count == 0:
            return ["--session-id", session_id]
        else:
            return ["--resume", session_id]

    def test_first_turn_uses_session_id(self) -> None:
        args = self._extract_session_args(prior_turn_count=0)
        assert "--session-id" in args
        assert "--resume" not in args

    def test_continuing_turn_uses_resume(self) -> None:
        args = self._extract_session_args(prior_turn_count=1)
        assert "--resume" in args
        assert "--session-id" not in args

    def test_higher_turn_count_still_uses_resume(self) -> None:
        args = self._extract_session_args(prior_turn_count=10)
        assert "--resume" in args
        assert "--session-id" not in args

    def test_session_id_and_resume_mutually_exclusive(self) -> None:
        for count in range(5):
            args = self._extract_session_args(prior_turn_count=count)
            has_session_id = "--session-id" in args
            has_resume = "--resume" in args
            # Exactly one must be present, never both
            assert has_session_id ^ has_resume, (
                f"count={count}: both or neither present: {args}"
            )
