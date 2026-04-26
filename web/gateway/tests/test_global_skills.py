"""Tests for global (user-level) skill scanning and API endpoints."""

from __future__ import annotations

from pathlib import Path
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient

import golem_gateway.skills as skills_mod
from golem_gateway.skills import get_global_skill_by_id, scan_global_skills


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_skill_dir(base: Path, skill_id: str, content: str = "") -> Path:
    """Create base/<skill_id>/SKILL.md and return the skill dir."""
    skill_dir = base / skill_id
    skill_dir.mkdir(parents=True, exist_ok=True)
    (skill_dir / "SKILL.md").write_text(content, encoding="utf-8")
    return skill_dir


def _patch_home(monkeypatch: pytest.MonkeyPatch, fake_home: Path) -> None:
    """Redirect Path.home() to fake_home."""
    monkeypatch.setattr(Path, "home", classmethod(lambda cls: fake_home))


def _reset_global_cache() -> None:
    """Clear module-level cache between tests."""
    skills_mod._global_scan_cache = None


# ---------------------------------------------------------------------------
# TestScanGlobalSkills
# ---------------------------------------------------------------------------


class TestScanGlobalSkills:
    def setup_method(self) -> None:
        _reset_global_cache()

    def test_returns_empty_when_dir_missing(
        self, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
    ) -> None:
        """No ~/.claude/skills/ → empty list, no error."""
        fake_home = tmp_path / "home_no_claude"
        fake_home.mkdir()
        _patch_home(monkeypatch, fake_home)

        result = scan_global_skills()
        assert result == []

    def test_scans_skill_dirs(
        self, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
    ) -> None:
        """Valid skill dirs under ~/.claude/skills/ are returned."""
        fake_home = tmp_path / "home"
        fake_home.mkdir()
        skills_base = fake_home / ".claude" / "skills"
        skills_base.mkdir(parents=True)

        _make_skill_dir(
            skills_base,
            "forge-init",
            "---\nname: Forge Init\ndescription: Initialize a golem project\n---\nBody text.",
        )
        _make_skill_dir(
            skills_base,
            "forge-team",
            "---\nname: Forge Team\ndescription: Manage team\n---\n",
        )
        _patch_home(monkeypatch, fake_home)

        result = scan_global_skills()
        ids = {s.id for s in result}
        assert "forge-init" in ids
        assert "forge-team" in ids
        assert len(result) == 2
        forge_init = next(s for s in result if s.id == "forge-init")
        assert forge_init.name == "Forge Init"
        assert forge_init.description == "Initialize a golem project"

    def test_skips_invalid_id_dirnames(
        self, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
    ) -> None:
        """Dirs with spaces or special chars are skipped (regex guard)."""
        fake_home = tmp_path / "home"
        fake_home.mkdir()
        skills_base = fake_home / ".claude" / "skills"
        skills_base.mkdir(parents=True)

        # Valid skill
        _make_skill_dir(skills_base, "valid-skill", "---\nname: Valid\n---\n")
        # Invalid names — create manually so they actually exist on disk
        bad = skills_base / "has space"
        bad.mkdir()
        (bad / "SKILL.md").write_text("x", encoding="utf-8")

        _patch_home(monkeypatch, fake_home)

        result = scan_global_skills()
        ids = {s.id for s in result}
        assert "valid-skill" in ids
        assert "has space" not in ids

    def test_skips_dir_without_skill_md(
        self, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
    ) -> None:
        """A directory without SKILL.md is silently ignored."""
        fake_home = tmp_path / "home"
        fake_home.mkdir()
        skills_base = fake_home / ".claude" / "skills"
        skills_base.mkdir(parents=True)

        # Dir with no SKILL.md
        no_md = skills_base / "no-skill-md"
        no_md.mkdir()
        (no_md / "README.md").write_text("x", encoding="utf-8")

        # Dir with SKILL.md
        _make_skill_dir(skills_base, "real-skill", "---\nname: Real\n---\n")

        _patch_home(monkeypatch, fake_home)

        result = scan_global_skills()
        assert len(result) == 1
        assert result[0].id == "real-skill"

    def test_mtime_cache_returns_same_object(
        self, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
    ) -> None:
        """Second call returns the cached list (same identity)."""
        fake_home = tmp_path / "home"
        fake_home.mkdir()
        skills_base = fake_home / ".claude" / "skills"
        skills_base.mkdir(parents=True)
        _make_skill_dir(skills_base, "cached-skill", "---\nname: Cached\n---\n")
        _patch_home(monkeypatch, fake_home)

        first = scan_global_skills()
        second = scan_global_skills()
        assert first is second  # cache hit → same list object


# ---------------------------------------------------------------------------
# TestGetGlobalSkill
# ---------------------------------------------------------------------------


class TestGetGlobalSkill:
    def setup_method(self) -> None:
        _reset_global_cache()

    def test_returns_none_for_traversal_attempt(
        self, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
    ) -> None:
        """skill_id containing path separators is blocked by regex."""
        fake_home = tmp_path / "home"
        fake_home.mkdir()
        _patch_home(monkeypatch, fake_home)

        # _VALID_SKILL_ID rejects anything with '/' or '.'
        assert get_global_skill_by_id("../evil") is None
        assert get_global_skill_by_id("some/path") is None
        assert get_global_skill_by_id("") is None

    def test_returns_skill_with_content(
        self, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
    ) -> None:
        """Valid skill_id resolves to a SkillDetail with correct fields."""
        fake_home = tmp_path / "home"
        fake_home.mkdir()
        skills_base = fake_home / ".claude" / "skills"
        skills_base.mkdir(parents=True)
        _make_skill_dir(
            skills_base,
            "forge-review",
            "---\nname: Forge Review\ndescription: Cross-review SOULs\n---\nFull body here.",
        )
        _patch_home(monkeypatch, fake_home)

        skill = get_global_skill_by_id("forge-review")
        assert skill is not None
        assert skill.id == "forge-review"
        assert skill.name == "Forge Review"
        assert "Full body here." in skill.content

    def test_returns_none_for_missing_skill(
        self, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
    ) -> None:
        """Non-existent skill_id returns None without raising."""
        fake_home = tmp_path / "home"
        fake_home.mkdir()
        (fake_home / ".claude" / "skills").mkdir(parents=True)
        _patch_home(monkeypatch, fake_home)

        assert get_global_skill_by_id("nonexistent") is None


# ---------------------------------------------------------------------------
# TestGlobalSkillsAPI
# ---------------------------------------------------------------------------


class TestGlobalSkillsAPI:
    def setup_method(self) -> None:
        _reset_global_cache()

    def _make_client(self) -> TestClient:
        from golem_gateway.main import app
        return TestClient(app)

    def test_list_endpoint_returns_200(
        self, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
    ) -> None:
        """GET /v1/skills/global returns 200 with skill list."""
        fake_home = tmp_path / "home"
        fake_home.mkdir()
        skills_base = fake_home / ".claude" / "skills"
        skills_base.mkdir(parents=True)
        _make_skill_dir(skills_base, "forge-init", "---\nname: Forge Init\n---\n")
        _patch_home(monkeypatch, fake_home)

        client = self._make_client()
        resp = client.get("/v1/skills/global")
        assert resp.status_code == 200
        data = resp.json()
        assert isinstance(data, list)
        assert any(s["id"] == "forge-init" for s in data)

    def test_detail_endpoint_returns_404_for_missing(
        self, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
    ) -> None:
        """GET /v1/skills/global/{missing} returns 404."""
        fake_home = tmp_path / "home"
        fake_home.mkdir()
        (fake_home / ".claude" / "skills").mkdir(parents=True)
        _patch_home(monkeypatch, fake_home)

        client = self._make_client()
        resp = client.get("/v1/skills/global/does-not-exist")
        assert resp.status_code == 404
