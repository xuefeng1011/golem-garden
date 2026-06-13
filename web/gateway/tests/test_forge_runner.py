"""Tests for golem_gateway.forge_runner — arg validation + env allowlist."""

from __future__ import annotations

from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from golem_gateway.config import ALLOWED_FORGE_COMMANDS
from golem_gateway.forge_runner import (
    ForgeRunner,
    _build_forge_env,
    _FORBIDDEN_ARG_CHARS,
)


# ---------------------------------------------------------------------------
# TestArgValidation
# ---------------------------------------------------------------------------


class TestArgValidation:
    @pytest.mark.asyncio
    async def test_rejects_unknown_command(self, tmp_path: Path) -> None:
        runner = ForgeRunner()
        with pytest.raises(ValueError, match="not in the allowed whitelist"):
            await runner.spawn(
                command="rm",
                args=[],
                project_id="p1",
                project_path=tmp_path,
            )

    @pytest.mark.asyncio
    @pytest.mark.parametrize("bad_char", sorted(_FORBIDDEN_ARG_CHARS))
    async def test_rejects_forbidden_chars_in_args(
        self, bad_char: str, tmp_path: Path
    ) -> None:
        runner = ForgeRunner()
        # Use a valid command so we get past command validation
        valid_cmd = next(iter(ALLOWED_FORGE_COMMANDS))
        bad_arg = f"safe{bad_char}injection"
        with pytest.raises(ValueError, match="forbidden characters"):
            await runner.spawn(
                command=valid_cmd,
                args=[bad_arg],
                project_id="p1",
                project_path=tmp_path,
            )

    @pytest.mark.asyncio
    async def test_rejects_too_many_args(self, tmp_path: Path) -> None:
        runner = ForgeRunner()
        valid_cmd = next(iter(ALLOWED_FORGE_COMMANDS))
        too_many = ["safe-arg"] * 31  # > _ARGS_MAX_COUNT (30)
        with pytest.raises(ValueError, match="too many args"):
            await runner.spawn(
                command=valid_cmd,
                args=too_many,
                project_id="p1",
                project_path=tmp_path,
            )

    @pytest.mark.asyncio
    async def test_rejects_oversized_arg(self, tmp_path: Path) -> None:
        runner = ForgeRunner()
        valid_cmd = next(iter(ALLOWED_FORGE_COMMANDS))
        oversized = "x" * 513  # > _ARG_MAX_CHARS (512)
        with pytest.raises(ValueError, match="exceeds"):
            await runner.spawn(
                command=valid_cmd,
                args=[oversized],
                project_id="p1",
                project_path=tmp_path,
            )

    @pytest.mark.asyncio
    async def test_rejects_missing_forge_sh(self, tmp_path: Path) -> None:
        """Raises RuntimeError when forge.sh does not exist at expected path."""
        runner = ForgeRunner()
        valid_cmd = next(iter(ALLOWED_FORGE_COMMANDS))
        fake_path = tmp_path / "nonexistent.sh"
        with patch("golem_gateway.forge_runner.FORGE_SH_PATH", fake_path):
            with pytest.raises(RuntimeError, match="forge.sh not found"):
                await runner.spawn(
                    command=valid_cmd,
                    args=[],
                    project_id="p1",
                    project_path=tmp_path,
                )


# ---------------------------------------------------------------------------
# TestEnvAllowlist
# ---------------------------------------------------------------------------


class TestEnvAllowlist:
    def test_build_forge_env_strips_secrets(
        self, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
    ) -> None:
        """Secret env vars must NOT pass through to forge subprocesses."""
        monkeypatch.setenv("ANTHROPIC_API_KEY", "secret-key")
        monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "aws-secret")
        monkeypatch.setenv("NPM_TOKEN", "npm-secret")
        env = _build_forge_env(tmp_path)
        assert "ANTHROPIC_API_KEY" not in env
        assert "AWS_SECRET_ACCESS_KEY" not in env
        assert "NPM_TOKEN" not in env

    def test_build_forge_env_sets_golem_project(
        self, tmp_path: Path
    ) -> None:
        env = _build_forge_env(tmp_path)
        assert "GOLEM_PROJECT" in env
        # Value should be a non-empty path string
        assert env["GOLEM_PROJECT"]

    def test_build_forge_env_sets_msys_guard(
        self, tmp_path: Path
    ) -> None:
        env = _build_forge_env(tmp_path)
        assert env.get("MSYS_NO_PATHCONV") == "1"
        assert env.get("MSYS2_ARG_CONV_EXCL") == "*"

    def test_build_forge_env_passes_allowed_vars(
        self, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
    ) -> None:
        monkeypatch.setenv("PATH", "/usr/bin:/bin")
        env = _build_forge_env(tmp_path)
        assert "PATH" in env


# ---------------------------------------------------------------------------
# TestPathConversion
# ---------------------------------------------------------------------------


class TestPathConversion:
    def test_to_bash_path_unix_passthrough(self) -> None:
        """On non-Windows (or any platform where os.name != 'nt'), path is unchanged."""
        import os
        from golem_gateway.config import to_bash_path

        if os.name != "nt":
            result = to_bash_path(Path("/home/user/project"))
            assert result == "/home/user/project"

    def test_to_bash_path_msys_drive_conversion(self, monkeypatch: pytest.MonkeyPatch) -> None:
        """Git Bash (msys): C:/foo/bar → /c/foo/bar on Windows."""
        import golem_gateway.config as cfg_mod
        monkeypatch.setattr(cfg_mod.os, "name", "nt")
        monkeypatch.setattr(cfg_mod, "_BASH_MOUNT", "msys")
        from golem_gateway.config import to_bash_path

        result = to_bash_path(Path("C:/foo/bar"))
        assert result == "/c/foo/bar"

    def test_to_bash_path_wsl_drive_conversion(self, monkeypatch: pytest.MonkeyPatch) -> None:
        """WSL: C:/foo/bar → /mnt/c/foo/bar on Windows."""
        import golem_gateway.config as cfg_mod
        monkeypatch.setattr(cfg_mod.os, "name", "nt")
        monkeypatch.setattr(cfg_mod, "_BASH_MOUNT", "wsl")
        from golem_gateway.config import to_bash_path

        result = to_bash_path(Path("C:/foo/bar"))
        assert result == "/mnt/c/foo/bar"

    def test_to_bash_path_windows_no_drive_passthrough(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Paths without a Windows drive letter are returned unchanged."""
        import golem_gateway.config as cfg_mod
        monkeypatch.setattr(cfg_mod.os, "name", "nt")
        monkeypatch.setattr(cfg_mod, "_BASH_MOUNT", "msys")
        from golem_gateway.config import to_bash_path

        result = to_bash_path("/c/already/converted")
        assert result == "/c/already/converted"


class TestBashResolution:
    def test_env_override_wins(self, monkeypatch: pytest.MonkeyPatch) -> None:
        """GOLEM_BASH_BIN override is honored verbatim."""
        import golem_gateway.config as cfg_mod
        monkeypatch.setenv("GOLEM_BASH_BIN", "/custom/bash")
        monkeypatch.setenv("GOLEM_BASH_MOUNT", "wsl")
        binpath, mount = cfg_mod._resolve_bash()
        assert binpath == "/custom/bash"
        assert mount == "wsl"

    def test_prefers_git_bash_over_wsl(self, monkeypatch: pytest.MonkeyPatch) -> None:
        """On Windows, a present Git Bash path is chosen with msys mount."""
        import golem_gateway.config as cfg_mod
        monkeypatch.delenv("GOLEM_BASH_BIN", raising=False)
        monkeypatch.delenv("GOLEM_BASH_MOUNT", raising=False)
        monkeypatch.setattr(cfg_mod.os, "name", "nt")
        git_bash = r"C:\Program Files\Git\bin\bash.exe"
        monkeypatch.setattr(
            cfg_mod.Path, "is_file", lambda self: str(self) == git_bash
        )
        binpath, mount = cfg_mod._resolve_bash()
        assert binpath == git_bash
        assert mount == "msys"
