"""Tests for golem_gateway.runs_store — masking, rolling GC, truncation, RUNS_DISABLE, schema."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

import golem_gateway.runs_store as rs
from golem_gateway import runs_store


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_REQUIRED_KEYS = [
    "run_id", "session_id", "soul", "model", "source",
    "ts_start", "duration_ms", "tokens_in", "tokens_out",
    "tokens_cache", "cost_usd", "result", "tool_counts",
]

_INT_KEYS = {"duration_ms", "tokens_in", "tokens_out", "tokens_cache"}
_FLOAT_KEYS = {"cost_usd"}
_DICT_KEYS = {"tool_counts"}


def _basic_persist(project_path: Path, *, run_id: str = "aaaaaaaa-0000-4000-a000-000000000001",
                   raw_lines: list[str] | None = None, **kwargs) -> None:
    defaults = dict(
        run_id=run_id,
        session_id="bbbbbbbb-0000-4000-a000-000000000002",
        soul_id="ryn",
        model="claude-3-5-sonnet-20241022",
        result="success",
        ts_start="2026-06-12T00:00:00+00:00",
        duration_ms=1000,
        usage={"input_tokens": 10, "output_tokens": 5, "cache_read_input_tokens": 2},
        tool_log=["bash", "bash", "read"],
        raw_lines=raw_lines or ['{"type":"text","text":"hello"}'],
        raw_truncated=False,
    )
    defaults.update(kwargs)
    rs.persist_run(project_path, **defaults)


# ---------------------------------------------------------------------------
# Masking tests (G5)
# ---------------------------------------------------------------------------

class TestMasking:
    def test_sk_key_masked(self) -> None:
        line = '{"key": "sk-abcdefghijklmnopqrst"}'
        result = rs._mask_line(line)
        assert "sk-abcdefghijklmnopqrst" not in result
        assert "***MASKED***" in result

    def test_sk_key_short_not_masked(self) -> None:
        # Less than 10 chars after "sk-" — should NOT be masked
        line = '{"key": "sk-short"}'
        result = rs._mask_line(line)
        assert "sk-short" in result

    def test_ghp_key_masked(self) -> None:
        line = '{"token": "ghp_ABCDEFGHIJ1234567890ABCDE"}'
        result = rs._mask_line(line)
        assert "ghp_ABCDEFGHIJ1234567890ABCDE" not in result
        assert "***MASKED***" in result

    def test_ghp_short_not_masked(self) -> None:
        # Less than 20 chars — should NOT be masked
        line = '{"token": "ghp_short123"}'
        result = rs._mask_line(line)
        assert "ghp_short123" in result

    def test_anthropic_key_masked_name_preserved(self) -> None:
        line = 'ANTHROPIC_API_KEY=sk-ant-real-key-here-123456'
        result = rs._mask_line(line)
        assert "sk-ant-real-key-here-123456" not in result
        assert "ANTHROPIC_KEY=***MASKED***" in result

    def test_openai_key_masked_name_preserved(self) -> None:
        line = 'OPENAI_API_KEY="sk-proj-secret-abc123"'
        result = rs._mask_line(line)
        assert "sk-proj-secret-abc123" not in result
        assert "OPENAI_KEY=***MASKED***" in result

    def test_plain_line_unchanged(self) -> None:
        line = '{"type": "text", "text": "hello world"}'
        result = rs._mask_line(line)
        assert result == line


# ---------------------------------------------------------------------------
# persist_run — basic write
# ---------------------------------------------------------------------------

class TestPersistRun:
    def test_creates_jsonl_and_meta(self, tmp_path: Path) -> None:
        _basic_persist(tmp_path)
        runs_dir = tmp_path / ".golem" / "runs"
        assert runs_dir.is_dir()
        jsonl = runs_dir / "aaaaaaaa-0000-4000-a000-000000000001.jsonl"
        meta = runs_dir / "aaaaaaaa-0000-4000-a000-000000000001.meta.json"
        assert jsonl.is_file()
        assert meta.is_file()

    def test_meta_contains_required_keys(self, tmp_path: Path) -> None:
        """G6 golden: all 13 required keys from spec/run-meta.schema.json present."""
        _basic_persist(tmp_path)
        meta_path = tmp_path / ".golem" / "runs" / "aaaaaaaa-0000-4000-a000-000000000001.meta.json"
        data = json.loads(meta_path.read_text(encoding="utf-8"))
        for key in _REQUIRED_KEYS:
            assert key in data, f"required key missing: {key}"

    def test_meta_key_types(self, tmp_path: Path) -> None:
        """G6: type validation for all required keys."""
        _basic_persist(tmp_path)
        meta_path = tmp_path / ".golem" / "runs" / "aaaaaaaa-0000-4000-a000-000000000001.meta.json"
        data = json.loads(meta_path.read_text(encoding="utf-8"))
        for k in _INT_KEYS:
            assert isinstance(data[k], int), f"{k} should be int, got {type(data[k])}"
        for k in _FLOAT_KEYS:
            assert isinstance(data[k], (int, float)), f"{k} should be number"
        for k in _DICT_KEYS:
            assert isinstance(data[k], dict), f"{k} should be dict"
        assert isinstance(data["run_id"], str)
        assert isinstance(data["soul"], str)
        assert isinstance(data["source"], str)
        assert data["source"] == "gateway"
        assert data["result"] in ("success", "fail", "timeout")

    def test_meta_token_counts(self, tmp_path: Path) -> None:
        _basic_persist(
            tmp_path,
            usage={"input_tokens": 100, "output_tokens": 50, "cache_read_input_tokens": 20,
                   "cache_creation_input_tokens": 5},
        )
        meta_path = tmp_path / ".golem" / "runs" / "aaaaaaaa-0000-4000-a000-000000000001.meta.json"
        data = json.loads(meta_path.read_text(encoding="utf-8"))
        assert data["tokens_in"] == 100
        assert data["tokens_out"] == 50
        assert data["tokens_cache"] == 25  # 20 + 5

    def test_meta_tool_counts(self, tmp_path: Path) -> None:
        _basic_persist(tmp_path, tool_log=["bash", "bash", "read", "bash"])
        meta_path = tmp_path / ".golem" / "runs" / "aaaaaaaa-0000-4000-a000-000000000001.meta.json"
        data = json.loads(meta_path.read_text(encoding="utf-8"))
        assert data["tool_counts"] == {"bash": 3, "read": 1}

    def test_raw_lines_written_masked(self, tmp_path: Path) -> None:
        raw = ['{"type":"text","text":"sk-abcdefghijklmnopqrst"}']
        _basic_persist(tmp_path, raw_lines=raw)
        jsonl = tmp_path / ".golem" / "runs" / "aaaaaaaa-0000-4000-a000-000000000001.jsonl"
        content = jsonl.read_text(encoding="utf-8")
        assert "sk-abcdefghijklmnopqrst" not in content
        assert "***MASKED***" in content


# ---------------------------------------------------------------------------
# Truncation marker (G1)
# ---------------------------------------------------------------------------

class TestTruncation:
    def test_truncated_marker_appended(self, tmp_path: Path) -> None:
        _basic_persist(
            tmp_path,
            raw_lines=['{"type":"text"}'],
            raw_truncated=True,
        )
        jsonl = tmp_path / ".golem" / "runs" / "aaaaaaaa-0000-4000-a000-000000000001.jsonl"
        lines = [l for l in jsonl.read_text(encoding="utf-8").splitlines() if l.strip()]
        assert lines[-1] == '{"type":"_truncated"}'

    def test_no_truncated_marker_when_not_truncated(self, tmp_path: Path) -> None:
        _basic_persist(
            tmp_path,
            raw_lines=['{"type":"text"}'],
            raw_truncated=False,
        )
        jsonl = tmp_path / ".golem" / "runs" / "aaaaaaaa-0000-4000-a000-000000000001.jsonl"
        content = jsonl.read_text(encoding="utf-8")
        assert "_truncated" not in content


# ---------------------------------------------------------------------------
# Rolling GC (RUNS_KEEP)
# ---------------------------------------------------------------------------

class TestRollingGC:
    def test_gc_deletes_oldest_beyond_keep(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        """With RUNS_KEEP=3, persisting a 4th run deletes the oldest pair."""
        monkeypatch.setattr(runs_store, "RUNS_KEEP", 3)

        ids = [f"cccccccc-0000-4000-a000-00000000000{i}" for i in range(1, 5)]
        for i, rid in enumerate(ids):
            _basic_persist(tmp_path, run_id=rid)
            # nudge mtime so files have distinct order
            jsonl = tmp_path / ".golem" / "runs" / f"{rid}.jsonl"
            import os, time as _time
            new_mtime = os.stat(jsonl).st_mtime + i
            os.utime(jsonl, (new_mtime, new_mtime))

        runs_dir = tmp_path / ".golem" / "runs"
        jsonl_files = list(runs_dir.glob("*.jsonl"))
        assert len(jsonl_files) == 3

        # Oldest (id[0]) should be gone; newest 3 (id[1..3]) should remain
        oldest_jsonl = runs_dir / f"{ids[0]}.jsonl"
        oldest_meta = runs_dir / f"{ids[0]}.meta.json"
        assert not oldest_jsonl.exists()
        assert not oldest_meta.exists()

        for rid in ids[1:]:
            assert (runs_dir / f"{rid}.jsonl").exists()
            assert (runs_dir / f"{rid}.meta.json").exists()


# ---------------------------------------------------------------------------
# RUNS_DISABLE no-op
# ---------------------------------------------------------------------------

class TestRunsDisable:
    def test_no_files_written_when_disabled(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setattr(runs_store, "RUNS_DISABLE", True)
        _basic_persist(tmp_path)
        runs_dir = tmp_path / ".golem" / "runs"
        assert not runs_dir.exists()


# ---------------------------------------------------------------------------
# Error resilience
# ---------------------------------------------------------------------------

class TestErrorResilience:
    def test_persist_does_not_raise_on_bad_path(self, tmp_path: Path) -> None:
        """persist_run swallows all exceptions — never raises."""
        bad_path = tmp_path / "nonexistent" / "project"
        # We can't make mkdir fail easily, but we can pass a file as project_path
        fake_file = tmp_path / "not_a_dir.txt"
        fake_file.write_text("x")
        # Should not raise
        try:
            rs.persist_run(
                fake_file,
                run_id="dddddddd-0000-4000-a000-000000000001",
                session_id="eeeeeeee-0000-4000-a000-000000000001",
                soul_id="ryn",
                model="test",
                result="fail",
                ts_start="2026-06-12T00:00:00+00:00",
                duration_ms=0,
                usage={},
                tool_log=[],
                raw_lines=[],
                raw_truncated=False,
            )
        except Exception as exc:
            pytest.fail(f"persist_run raised unexpectedly: {exc}")
