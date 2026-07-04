"""Tests for golem_gateway.forge_runner — arg validation + env allowlist."""

from __future__ import annotations

import asyncio
import os
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from golem_gateway.config import ALLOWED_FORGE_COMMANDS, MAX_FLOW_SECONDS, MAX_FORGE_SECONDS
from golem_gateway.forge_runner import (
    ForgeRun,
    ForgeRunner,
    _build_forge_env,
    _run_timeout_seconds,
    _FORBIDDEN_ARG_CHARS,
)


def _make_run(run_id: str, proc=None, command: str = "flow", args: list[str] | None = None) -> ForgeRun:
    """Minimal ForgeRun for terminate/cancel tests (no real subprocess)."""
    return ForgeRun(
        run_id=run_id,
        command=command,
        args=["run", "x"] if args is None else args,
        project_id="p",
        project_path=Path("."),
        proc=proc,
        queue=asyncio.Queue(),
        done=asyncio.Event(),
        started_at=0.0,
    )


# ---------------------------------------------------------------------------
# TestRunTimeoutSelection — flow/mission run은 장기 상한, 그 외 단기 상한
# ---------------------------------------------------------------------------


class TestRunTimeoutSelection:
    def test_flow_run_gets_long_ceiling(self) -> None:
        run = _make_run("r1", command="flow", args=["run", "abc"])
        assert _run_timeout_seconds(run) == MAX_FLOW_SECONDS

    def test_mission_run_gets_long_ceiling(self) -> None:
        run = _make_run("r2", command="mission", args=["run", "msn_1"])
        assert _run_timeout_seconds(run) == MAX_FLOW_SECONDS

    def test_flow_status_keeps_short_ceiling(self) -> None:
        run = _make_run("r3", command="flow", args=["status", "abc"])
        assert _run_timeout_seconds(run) == MAX_FORGE_SECONDS

    def test_other_commands_keep_short_ceiling(self) -> None:
        run = _make_run("r4", command="status", args=[])
        assert _run_timeout_seconds(run) == MAX_FORGE_SECONDS

    def test_long_ceiling_exceeds_short(self) -> None:
        assert MAX_FLOW_SECONDS > MAX_FORGE_SECONDS

    def test_studio_run_gets_long_ceiling(self) -> None:
        run = _make_run("r5", command="studio", args=["run", "studio-1"])
        assert _run_timeout_seconds(run) == MAX_FLOW_SECONDS

    def test_studio_design_gets_long_ceiling(self) -> None:
        run = _make_run("r6", command="studio", args=["design", "build a research team"])
        assert _run_timeout_seconds(run) == MAX_FLOW_SECONDS

    def test_studio_status_keeps_short_ceiling(self) -> None:
        run = _make_run("r7", command="studio", args=["status"])
        assert _run_timeout_seconds(run) == MAX_FORGE_SECONDS


class TestTerminateAndCancel:
    @pytest.mark.asyncio
    async def test_terminate_run_evicts_and_sets_done(self):
        runner = ForgeRunner()
        run = _make_run("rid-1")
        runner._runs["rid-1"] = run

        await runner.terminate_run("rid-1")

        assert await runner.get_run("rid-1") is None
        assert run.done.is_set()

    @pytest.mark.asyncio
    async def test_terminate_run_unknown_is_noop(self):
        runner = ForgeRunner()
        # must not raise
        await runner.terminate_run("does-not-exist")

    @pytest.mark.asyncio
    async def test_terminate_proc_tree_posix_graceful(self):
        # Force POSIX path so taskkill is skipped; assert graceful terminate→wait.
        proc = MagicMock()
        proc.returncode = None
        proc.pid = 4242
        proc.terminate = MagicMock()
        proc.kill = MagicMock()
        proc.wait = AsyncMock(return_value=0)

        with patch("golem_gateway.forge_runner.os.name", "posix"):
            await ForgeRunner._terminate_proc_tree(proc)

        proc.terminate.assert_called_once()
        proc.wait.assert_awaited()
        proc.kill.assert_not_called()

    @pytest.mark.asyncio
    async def test_terminate_proc_tree_windows_taskkill_tree(self):
        """nt 분기 — taskkill /F /T /PID 로 네이티브 트리 kill (주 플랫폼 경로).

        claude.exe 손자 프로세스 고아화(flow step 영구 running의 원인)를 막는
        핵심 분기인데 지금까지 posix 강제 테스트만 있었다.
        """
        proc = MagicMock()
        proc.returncode = None
        proc.pid = 4242
        proc.terminate = MagicMock()
        proc.kill = MagicMock()
        proc.wait = AsyncMock(return_value=0)

        tk_proc = MagicMock()
        tk_proc.wait = AsyncMock(return_value=0)
        create_exec = AsyncMock(return_value=tk_proc)

        with patch("golem_gateway.forge_runner.os.name", "nt"), \
             patch("golem_gateway.forge_runner.asyncio.create_subprocess_exec", create_exec):
            await ForgeRunner._terminate_proc_tree(proc)

        create_exec.assert_awaited_once()
        argv = create_exec.await_args.args
        assert argv[:4] == ("taskkill", "/F", "/T", "/PID")
        assert argv[4] == "4242"
        tk_proc.wait.assert_awaited()
        # taskkill 성공 후에도 graceful fallback 은 안전하게 실행돼야 한다
        # (이미 죽었으면 ProcessLookupError 무시 경로)

    @pytest.mark.asyncio
    async def test_terminate_proc_tree_windows_taskkill_missing_falls_back(self):
        """taskkill 자체가 없거나(OSError) 실패해도 terminate→kill 폴백으로 진행."""
        proc = MagicMock()
        proc.returncode = None
        proc.pid = 4242
        proc.terminate = MagicMock()
        proc.kill = MagicMock()
        proc.wait = AsyncMock(return_value=0)

        create_exec = AsyncMock(side_effect=OSError("taskkill not found"))

        with patch("golem_gateway.forge_runner.os.name", "nt"), \
             patch("golem_gateway.forge_runner.asyncio.create_subprocess_exec", create_exec):
            await ForgeRunner._terminate_proc_tree(proc)

        proc.terminate.assert_called_once()
        proc.wait.assert_awaited()

    @pytest.mark.asyncio
    async def test_delete_forge_run_endpoint(self):
        """DELETE /v1/forge-runs/{id} → 204 + evicted; unknown → 404."""
        from httpx import ASGITransport, AsyncClient

        from golem_gateway.main import app

        runner = ForgeRunner()
        app.state.forge_runner = runner
        runner._runs["rid-http"] = _make_run("rid-http")

        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.delete("/v1/forge-runs/rid-http")
            assert resp.status_code == 204, resp.text
            assert await runner.get_run("rid-http") is None

            resp = await client.delete("/v1/forge-runs/rid-http")
            assert resp.status_code == 404


# ---------------------------------------------------------------------------
# TestAllowedCommands
# ---------------------------------------------------------------------------


class TestAllowedCommands:
    def test_studio_is_whitelisted(self) -> None:
        """Flow Studio (STUDIO_PLAN.md §4) — `studio` must be dispatchable."""
        assert "studio" in ALLOWED_FORGE_COMMANDS


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
    @pytest.mark.parametrize("traversal", ["../etc", "a/../../b", "..\\windows", "run/../x"])
    async def test_rejects_path_traversal_args(
        self, traversal: str, tmp_path: Path
    ) -> None:
        """flow/mission id 류 인자의 ../ 시퀀스는 REST 정규식 우회 방지 차원에서 거부."""
        runner = ForgeRunner()
        valid_cmd = next(iter(ALLOWED_FORGE_COMMANDS))
        with pytest.raises(ValueError, match="traversal"):
            await runner.spawn(
                command=valid_cmd,
                args=[traversal],
                project_id="p1",
                project_path=tmp_path,
            )

    @pytest.mark.asyncio
    async def test_allows_bare_dots_in_prose(self, tmp_path: Path) -> None:
        """산문 인자의 '..' 자체(시퀀스 아님)는 합법 — 과잉 차단 방지."""
        runner = ForgeRunner()
        fake_path = tmp_path / "nonexistent.sh"
        # forge.sh 부재 RuntimeError 까지 도달하면 인자 검증은 통과한 것
        with patch("golem_gateway.forge_runner.FORGE_SH_PATH", fake_path):
            with pytest.raises(RuntimeError, match="forge.sh not found"):
                await runner.spawn(
                    command=next(iter(ALLOWED_FORGE_COMMANDS)),
                    args=["계속.. 진행하라"],
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
        self, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
    ) -> None:
        # MSYS 가드는 os.name == "nt" 일 때만 설정된다(9b93c9c 포터빌리티 가드).
        # 비Windows 호스트에서도 Windows 분기를 검증하기 위해 os.name 을 패치한다.
        # _build_forge_env → to_bash_path 통합 경로까지 Windows 분기를 타도록
        # forge_runner 와 config 양쪽 모듈의 os.name 을 함께 패치한다 (Zen 리뷰).
        import golem_gateway.config as cfg_mod
        import golem_gateway.forge_runner as fr

        monkeypatch.setattr(fr.os, "name", "nt")
        monkeypatch.setattr(cfg_mod.os, "name", "nt")
        env = _build_forge_env(tmp_path)
        assert env.get("MSYS_NO_PATHCONV") == "1"
        assert env.get("MSYS2_ARG_CONV_EXCL") == "*"

    def test_build_forge_env_passes_allowed_vars(
        self, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
    ) -> None:
        monkeypatch.setenv("PATH", "/usr/bin:/bin")
        env = _build_forge_env(tmp_path)
        assert "PATH" in env

    def test_build_forge_env_defaults_lang_when_absent(
        self, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
    ) -> None:
        """LANG/LC_ALL 부재(Windows 서비스) → C.UTF-8 기본값.

        bash C 로케일의 바이트 단위 ${var:0:N} 슬라이싱이 한글 멀티바이트를
        중간에서 잘라 state.json 을 오염시키던 결함의 게이트웨이측 방어."""
        monkeypatch.delenv("LANG", raising=False)
        monkeypatch.delenv("LC_ALL", raising=False)
        env = _build_forge_env(tmp_path)
        assert env["LANG"] == "C.UTF-8"

    def test_build_forge_env_keeps_parent_lang(
        self, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
    ) -> None:
        monkeypatch.setenv("LANG", "ko_KR.UTF-8")
        env = _build_forge_env(tmp_path)
        assert env["LANG"] == "ko_KR.UTF-8"

    def test_build_forge_env_lc_all_alone_suffices(
        self, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
    ) -> None:
        monkeypatch.delenv("LANG", raising=False)
        monkeypatch.setenv("LC_ALL", "en_US.UTF-8")
        env = _build_forge_env(tmp_path)
        assert "LANG" not in env
        assert env["LC_ALL"] == "en_US.UTF-8"


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

    @pytest.mark.skipif(
        os.name != "nt",
        reason="Windows Git Bash 경로 해석 — PosixPath 로는 Windows 경로 의미론"
        "(Path(r'C:\\...').parent)을 시뮬레이션할 수 없어 비Windows 에서 스킵",
    )
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
