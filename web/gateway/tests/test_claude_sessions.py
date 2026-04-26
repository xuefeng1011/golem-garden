"""Tests for golem_gateway.claude_sessions — sanitization, delete, GC."""

from __future__ import annotations

import uuid
from pathlib import Path

import pytest

from golem_gateway.claude_sessions import (
    _UUID_RE,
    _sanitize_cwd,
    claude_sessions_dir,
    delete_claude_session,
    gc_orphaned_claude_sessions,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _fake_sessions_dir(tmp_path: Path, project_path: Path) -> Path:
    """Create a fake ~/.claude/projects/<sanitized>/ rooted at tmp_path."""
    from golem_gateway.claude_sessions import _sanitize_cwd

    d = tmp_path / ".claude" / "projects" / _sanitize_cwd(project_path)
    d.mkdir(parents=True, exist_ok=True)
    return d


def _make_session_file(sessions_dir: Path, session_id: str) -> Path:
    p = sessions_dir / f"{session_id}.jsonl"
    p.write_text('{"type":"session"}\n', encoding="utf-8")
    return p


# ---------------------------------------------------------------------------
# TestSanitization
# ---------------------------------------------------------------------------


class TestSanitization:
    def test_sanitize_basic_unix_path(self) -> None:
        result = _sanitize_cwd(Path("/home/user/my-project"))
        # Path.resolve() on Windows prepends the drive letter (e.g. C:),
        # so we only assert the path segments are present, not the exact prefix.
        assert "home-user-my-project" in result
        assert not result.startswith("-")
        assert not result.endswith("-")

    def test_sanitize_windows_style_path(self, tmp_path: Path) -> None:
        # On Windows Path("/c/01-xuefeng/...").resolve() yields C:\c\01-xuefeng\...
        # so sanitized form includes the drive prefix.
        result = _sanitize_cwd(Path("/c/01-xuefeng/08-ai/golem-garden"))
        assert "01-xuefeng-08-ai-golem-garden" in result
        assert not result.startswith("-")
        assert not result.endswith("-")

    def test_sanitize_handles_spaces(self) -> None:
        result = _sanitize_cwd(Path("/home/user/my project"))
        assert "home-user-my-project" in result
        assert not result.startswith("-")
        assert not result.endswith("-")

    def test_sanitize_handles_korean_path(self) -> None:
        # Korean chars are non-alphanumeric → collapsed to hyphens
        result = _sanitize_cwd(Path("/c/Users/최설봉/project"))
        assert "-" in result
        assert "project" in result
        assert not result.startswith("-")
        assert not result.endswith("-")

    def test_sanitize_no_leading_trailing_hyphens(self) -> None:
        result = _sanitize_cwd(Path("/foo/bar"))
        assert not result.startswith("-")
        assert not result.endswith("-")

    def test_claude_sessions_dir_uses_home(self, monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
        monkeypatch.setattr(Path, "home", staticmethod(lambda: tmp_path))
        project = Path("/some/project")
        expected = tmp_path / ".claude" / "projects" / _sanitize_cwd(project)
        assert claude_sessions_dir(project) == expected


# ---------------------------------------------------------------------------
# TestUUIDPattern
# ---------------------------------------------------------------------------


class TestUUIDPattern:
    def test_valid_uuid(self) -> None:
        assert _UUID_RE.match("70586057-b03b-46b5-b991-ff22e8b438b1")

    def test_invalid_stem(self) -> None:
        assert not _UUID_RE.match("memory")
        assert not _UUID_RE.match("projects")
        assert not _UUID_RE.match("not-a-uuid-at-all")

    def test_uppercase_uuid_accepted(self) -> None:
        assert _UUID_RE.match("70586057-B03B-46B5-B991-FF22E8B438B1")


# ---------------------------------------------------------------------------
# TestDeleteClaudeSession
# ---------------------------------------------------------------------------


class TestDeleteClaudeSession:
    def test_returns_false_when_dir_missing(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setattr(Path, "home", staticmethod(lambda: tmp_path))
        project = tmp_path / "nonexistent_project"
        sid = str(uuid.uuid4())
        assert delete_claude_session(project, sid) is False

    def test_deletes_existing_jsonl(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setattr(Path, "home", staticmethod(lambda: tmp_path))
        project = tmp_path / "myproject"
        project.mkdir()
        sessions_dir = _fake_sessions_dir(tmp_path, project)
        sid = str(uuid.uuid4())
        f = _make_session_file(sessions_dir, sid)
        assert f.exists()

        result = delete_claude_session(project, sid)

        assert result is True
        assert not f.exists()

    def test_returns_false_when_file_missing(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setattr(Path, "home", staticmethod(lambda: tmp_path))
        project = tmp_path / "myproject"
        project.mkdir()
        _fake_sessions_dir(tmp_path, project)  # dir exists but no file
        sid = str(uuid.uuid4())

        assert delete_claude_session(project, sid) is False

    def test_does_not_raise_on_missing_file(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setattr(Path, "home", staticmethod(lambda: tmp_path))
        project = tmp_path / "myproject"
        project.mkdir()
        # No sessions dir at all — should not raise
        sid = str(uuid.uuid4())
        result = delete_claude_session(project, sid)
        assert result is False

    def test_rejects_non_uuid_session_id(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setattr(Path, "home", staticmethod(lambda: tmp_path))
        project = tmp_path / "myproject"
        project.mkdir()
        sessions_dir = _fake_sessions_dir(tmp_path, project)
        # Create a file with non-UUID name — should never be deleted
        bad_name = "not-a-uuid"
        f = sessions_dir / f"{bad_name}.jsonl"
        f.write_text("data")

        result = delete_claude_session(project, bad_name)

        assert result is False
        assert f.exists()  # file untouched


# ---------------------------------------------------------------------------
# TestGcOrphaned
# ---------------------------------------------------------------------------


class TestGcOrphaned:
    def test_returns_zero_when_dir_missing(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setattr(Path, "home", staticmethod(lambda: tmp_path))
        project = tmp_path / "ghost_project"
        result = gc_orphaned_claude_sessions(project, set())
        assert result == 0

    def test_deletes_only_orphans(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setattr(Path, "home", staticmethod(lambda: tmp_path))
        project = tmp_path / "myproject"
        project.mkdir()
        sessions_dir = _fake_sessions_dir(tmp_path, project)

        # Create 5 UUID sessions
        ids = [str(uuid.uuid4()) for _ in range(5)]
        for sid in ids:
            _make_session_file(sessions_dir, sid)

        # Mark 3 as known — 2 should be deleted
        known = set(ids[:3])
        orphans = set(ids[3:])

        deleted = gc_orphaned_claude_sessions(project, known)

        assert deleted == 2
        for sid in known:
            assert (sessions_dir / f"{sid}.jsonl").exists()
        for sid in orphans:
            assert not (sessions_dir / f"{sid}.jsonl").exists()

    def test_skips_non_uuid_files(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setattr(Path, "home", staticmethod(lambda: tmp_path))
        project = tmp_path / "myproject"
        project.mkdir()
        sessions_dir = _fake_sessions_dir(tmp_path, project)

        # Non-UUID file (e.g. memory artifact) must never be touched
        safe_file = sessions_dir / "not-a-uuid.jsonl"
        safe_file.write_text("keep me")

        deleted = gc_orphaned_claude_sessions(project, set())

        assert deleted == 0
        assert safe_file.exists()

    def test_skips_directories(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setattr(Path, "home", staticmethod(lambda: tmp_path))
        project = tmp_path / "myproject"
        project.mkdir()
        sessions_dir = _fake_sessions_dir(tmp_path, project)

        # Subdir named like a UUID (claude creates these for subagent metadata)
        subdir = sessions_dir / str(uuid.uuid4())
        subdir.mkdir()

        deleted = gc_orphaned_claude_sessions(project, set())

        assert deleted == 0
        assert subdir.exists()

    def test_returns_zero_when_all_known(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setattr(Path, "home", staticmethod(lambda: tmp_path))
        project = tmp_path / "myproject"
        project.mkdir()
        sessions_dir = _fake_sessions_dir(tmp_path, project)

        ids = [str(uuid.uuid4()) for _ in range(3)]
        for sid in ids:
            _make_session_file(sessions_dir, sid)

        deleted = gc_orphaned_claude_sessions(project, set(ids))
        assert deleted == 0
