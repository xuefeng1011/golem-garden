"""Tests for golem_gateway.registry — path validation + CRUD."""

from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import patch

import pytest

from golem_gateway.registry import ProjectRegistry, _validate_project_path


# ---------------------------------------------------------------------------
# TestPathValidation
# ---------------------------------------------------------------------------


class TestPathValidation:
    def test_rejects_empty_path(self) -> None:
        with pytest.raises(ValueError, match="empty"):
            _validate_project_path("")

    def test_rejects_whitespace_only_path(self) -> None:
        with pytest.raises(ValueError, match="empty"):
            _validate_project_path("   ")

    def test_rejects_nonexistent_path(self, tmp_path: Path) -> None:
        missing = tmp_path / "does_not_exist"
        with pytest.raises(ValueError, match="does not exist"):
            _validate_project_path(str(missing))

    def test_rejects_file_not_directory(self, tmp_path: Path) -> None:
        f = tmp_path / "file.txt"
        f.write_text("x")
        with pytest.raises(ValueError, match="does not exist or is not a directory"):
            _validate_project_path(str(f))

    def test_rejects_path_outside_home(
        self, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
    ) -> None:
        """Path outside home and without GOLEM_EXTRA_PROJECT_ROOTS must be rejected."""
        home_fake = tmp_path / "fake_home"
        home_fake.mkdir()
        outside = tmp_path / "outside_dir"
        outside.mkdir()
        monkeypatch.delenv("GOLEM_EXTRA_PROJECT_ROOTS", raising=False)
        with patch("golem_gateway.registry.Path.home", return_value=home_fake):
            with pytest.raises(ValueError, match="inside Path.home"):
                _validate_project_path(str(outside))

    def test_accepts_path_inside_home(
        self, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
    ) -> None:
        home_fake = tmp_path / "fake_home"
        inside = home_fake / "projects" / "myproject"
        inside.mkdir(parents=True)
        monkeypatch.delenv("GOLEM_EXTRA_PROJECT_ROOTS", raising=False)
        with patch("golem_gateway.registry.Path.home", return_value=home_fake):
            result = _validate_project_path(str(inside))
        assert result.is_dir()

    def test_accepts_path_in_extra_roots_env(
        self, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
    ) -> None:
        home_fake = tmp_path / "fake_home"
        home_fake.mkdir()
        extra_root = tmp_path / "extra_root"
        project_dir = extra_root / "project_x"
        project_dir.mkdir(parents=True)
        monkeypatch.setenv("GOLEM_EXTRA_PROJECT_ROOTS", str(extra_root))
        with patch("golem_gateway.registry.Path.home", return_value=home_fake):
            result = _validate_project_path(str(project_dir))
        assert result.is_dir()


# ---------------------------------------------------------------------------
# TestRegistryCRUD
# ---------------------------------------------------------------------------


class TestRegistryCRUD:
    async def _make_registry(self, registry_file: Path) -> ProjectRegistry:
        """Return a fresh ProjectRegistry pointed at temp_registry."""
        r = ProjectRegistry()
        await r.load()
        return r

    @pytest.mark.asyncio
    async def test_create_list_delete_roundtrip(
        self, temp_registry: Path, tmp_path: Path
    ) -> None:
        project_dir = tmp_path / "myproject"
        project_dir.mkdir()
        r = await self._make_registry(temp_registry)

        proj = await r.create(name="MyProject", path=str(project_dir))
        assert proj.name == "MyProject"
        assert proj.id

        items = await r.list()
        assert len(items) == 1
        assert items[0].id == proj.id

        deleted = await r.delete(proj.id)
        assert deleted is True

        items_after = await r.list()
        assert items_after == []

    @pytest.mark.asyncio
    async def test_delete_unknown_returns_false(
        self, temp_registry: Path
    ) -> None:
        r = await self._make_registry(temp_registry)
        assert await r.delete("nonexistent-id") is False

    @pytest.mark.asyncio
    async def test_duplicate_path_rejected(
        self, temp_registry: Path, tmp_path: Path
    ) -> None:
        project_dir = tmp_path / "dup_project"
        project_dir.mkdir()
        r = await self._make_registry(temp_registry)

        await r.create(name="First", path=str(project_dir))
        with pytest.raises(ValueError, match="already registered"):
            await r.create(name="Second", path=str(project_dir))

    @pytest.mark.asyncio
    async def test_list_returns_copies_not_references(
        self, temp_registry: Path, tmp_path: Path
    ) -> None:
        """F5: mutating returned list items must not corrupt registry state."""
        project_dir = tmp_path / "immutable_check"
        project_dir.mkdir()
        r = await self._make_registry(temp_registry)
        await r.create(name="Original", path=str(project_dir))

        items = await r.list()
        original_name = items[0].name
        items[0].name = "MUTATED"

        items_again = await r.list()
        assert items_again[0].name == original_name
        assert items_again[0].name != "MUTATED"

    @pytest.mark.asyncio
    async def test_atomic_write_survives_stale_tmp(
        self, temp_registry: Path, tmp_path: Path
    ) -> None:
        """If a .json.tmp exists from a prior crash, the registry still loads cleanly."""
        project_dir = tmp_path / "atomic_project"
        project_dir.mkdir()
        r = await self._make_registry(temp_registry)
        await r.create(name="Atomica", path=str(project_dir))

        # Simulate a stale / corrupt .json.tmp left from a prior crashed write.
        stale_tmp = temp_registry.with_suffix(".json.tmp")
        stale_tmp.write_text("CORRUPT{{{", encoding="utf-8")

        # Load a fresh registry instance — must still read the real .json.
        r2 = ProjectRegistry()
        await r2.load()
        items = await r2.list()
        assert len(items) == 1
        assert items[0].name == "Atomica"

    @pytest.mark.asyncio
    async def test_get_returns_copy(
        self, temp_registry: Path, tmp_path: Path
    ) -> None:
        project_dir = tmp_path / "get_copy"
        project_dir.mkdir()
        r = await self._make_registry(temp_registry)
        proj = await r.create(name="GetMe", path=str(project_dir))

        fetched = await r.get(proj.id)
        assert fetched is not None
        assert fetched.id == proj.id
        fetched.name = "MUTATED"

        fetched2 = await r.get(proj.id)
        assert fetched2 is not None
        assert fetched2.name == "GetMe"

    @pytest.mark.asyncio
    async def test_get_unknown_returns_none(self, temp_registry: Path) -> None:
        r = await self._make_registry(temp_registry)
        assert await r.get("no-such-id") is None
