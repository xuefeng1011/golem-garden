"""Tests for POST/GET /v1/studios (Flow Studio — STUDIO_PLAN.md §4).

Mirrors test_api_flows.py style: bare ASGITransport + a `_prime_app_state`
autouse fixture (lifespan doesn't run under ASGITransport), real
ProjectRegistry backed by the autouse `temp_registry` fixture from conftest
(redirects ~/.golem/projects.json + Path.home() to a tmp dir).

`_run_studio_init` is monkeypatched per-test: a no-op success for the
create/list/duplicate/validation cases, and a failing stub for the rollback
case — this keeps the tests independent of forge.sh/bash actually existing.
"""

from __future__ import annotations

import asyncio
import json
import logging
from pathlib import Path

import pytest
from httpx import ASGITransport, AsyncClient

import golem_gateway.api_studios as _studios_mod
from golem_gateway.main import app
from golem_gateway.registry import ProjectRegistry


# ---------------------------------------------------------------------------
# Autouse fixtures
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def _prime_app_state() -> None:
    """Set app.state.registry if the lifespan hasn't done it yet."""
    if not hasattr(app.state, "registry"):
        app.state.registry = ProjectRegistry()


@pytest.fixture()
def _init_ok(monkeypatch: pytest.MonkeyPatch) -> None:
    """Stub `forge studio init` as an async no-op success."""

    async def _noop(project_path: Path, name: str, goal: str) -> str | None:  # noqa: ARG001
        return None

    monkeypatch.setattr(_studios_mod, "_run_studio_init", _noop)


@pytest.fixture()
def _init_fails(monkeypatch: pytest.MonkeyPatch) -> None:
    """Stub `forge studio init` as an async failure (nonzero rc)."""

    async def _fail(project_path: Path, name: str, goal: str) -> str | None:  # noqa: ARG001
        return "forge studio init exited rc=1"

    monkeypatch.setattr(_studios_mod, "_run_studio_init", _fail)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


async def _post_studio(body: dict):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        return await client.post("/v1/studios", json=body)


async def _get_studios():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        return await client.get("/v1/studios")


async def _get_projects():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        return await client.get("/v1/projects")


async def _delete_studio(studio_id: str):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        return await client.delete(f"/v1/studios/{studio_id}")


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_create_studio_happy_path(_init_ok, tmp_path: Path) -> None:
    studio_dir = tmp_path / "studio_a"
    studio_dir.mkdir()

    resp = await _post_studio({"name": "Studio A", "path": str(studio_dir), "goal": "research"})
    assert resp.status_code == 201, resp.text
    data = resp.json()
    assert data["kind"] == "studio"
    assert data["name"] == "Studio A"
    assert data["path"]


@pytest.mark.asyncio
async def test_created_studio_appears_in_studios_not_projects(
    _init_ok, tmp_path: Path
) -> None:
    studio_dir = tmp_path / "studio_b"
    studio_dir.mkdir()

    resp = await _post_studio({"name": "Studio B", "path": str(studio_dir), "goal": ""})
    assert resp.status_code == 201, resp.text
    studio_id = resp.json()["id"]

    studios_resp = await _get_studios()
    assert studios_resp.status_code == 200
    assert any(s["id"] == studio_id for s in studios_resp.json())

    projects_resp = await _get_projects()
    assert projects_resp.status_code == 200
    assert all(p["id"] != studio_id for p in projects_resp.json())


@pytest.mark.asyncio
async def test_duplicate_path_returns_409(_init_ok, tmp_path: Path) -> None:
    studio_dir = tmp_path / "studio_dup"
    studio_dir.mkdir()

    first = await _post_studio({"name": "First", "path": str(studio_dir), "goal": ""})
    assert first.status_code == 201, first.text

    second = await _post_studio({"name": "Second", "path": str(studio_dir), "goal": ""})
    assert second.status_code == 409, second.text


@pytest.mark.asyncio
async def test_missing_dir_is_auto_created(_init_ok, tmp_path: Path) -> None:
    """스튜디오는 '새 폴더 지정' UX — 허용 루트 안의 미존재 경로는 자동 생성된다."""
    missing_dir = tmp_path / "brand_new" / "studio_dir"
    assert not missing_dir.exists()

    resp = await _post_studio({"name": "Auto Create", "path": str(missing_dir), "goal": ""})
    assert resp.status_code == 201, resp.text
    assert missing_dir.is_dir()


@pytest.mark.asyncio
async def test_path_that_is_a_file_returns_400(_init_ok, tmp_path: Path) -> None:
    file_path = tmp_path / "not_a_dir.txt"
    file_path.write_text("x", encoding="utf-8")

    resp = await _post_studio({"name": "File Path", "path": str(file_path), "goal": ""})
    assert resp.status_code == 400, resp.text


@pytest.mark.asyncio
async def test_path_outside_allowed_roots_returns_400(
    _init_ok, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """허용 루트(home/GOLEM_EXTRA_PROJECT_ROOTS) 밖이면 미존재 경로라도 생성하지 않는다."""
    monkeypatch.delenv("GOLEM_EXTRA_PROJECT_ROOTS", raising=False)
    outside = tmp_path.parent / f"{tmp_path.name}_outside_home" / "studio"

    resp = await _post_studio({"name": "Outside", "path": str(outside), "goal": ""})
    assert resp.status_code == 400, resp.text
    assert not outside.exists()


@pytest.mark.asyncio
async def test_goal_with_newline_returns_400(_init_ok, tmp_path: Path) -> None:
    studio_dir = tmp_path / "studio_newline_goal"
    studio_dir.mkdir()

    resp = await _post_studio(
        {"name": "Newline Goal", "path": str(studio_dir), "goal": "line1\nline2"}
    )
    assert resp.status_code == 400, resp.text


@pytest.mark.asyncio
async def test_init_failure_rolls_back_registry(_init_fails, tmp_path: Path) -> None:
    """Init failure on an auto-created dir rolls back BOTH the registry entry
    and the directory itself — a studio with no scaffold must not linger."""
    auto_dir = tmp_path / "studio_rollback_auto" / "studio_dir"
    assert not auto_dir.exists()

    resp = await _post_studio({"name": "Rollback Me", "path": str(auto_dir), "goal": ""})
    assert resp.status_code == 500, resp.text

    studios_resp = await _get_studios()
    assert studios_resp.status_code == 200
    assert all(s["name"] != "Rollback Me" for s in studios_resp.json())
    assert not auto_dir.exists()


@pytest.mark.asyncio
async def test_init_failure_preserves_pre_existing_dir(
    _init_fails, tmp_path: Path
) -> None:
    """A pre-existing directory (registered, not auto-created) must survive
    rollback untouched — only directories WE created get removed."""
    studio_dir = tmp_path / "studio_rollback_pre_existing"
    studio_dir.mkdir()
    marker = studio_dir / "marker.txt"
    marker.write_text("keep me", encoding="utf-8")

    resp = await _post_studio(
        {"name": "Rollback Pre-Existing", "path": str(studio_dir), "goal": ""}
    )
    assert resp.status_code == 500, resp.text
    assert studio_dir.is_dir()
    assert marker.is_file()


@pytest.mark.asyncio
async def test_path_with_newline_returns_400(_init_ok, tmp_path: Path) -> None:
    studio_dir = tmp_path / "studio_newline_path"
    studio_dir.mkdir()
    bad_path = f"{studio_dir}\nline2"

    resp = await _post_studio({"name": "Newline Path", "path": bad_path, "goal": ""})
    assert resp.status_code == 400, resp.text


@pytest.mark.asyncio
async def test_intermediate_path_component_is_a_file_returns_400(
    _init_ok, tmp_path: Path
) -> None:
    """A parent segment that is a regular file (not a directory) must 400,
    not raise an unhandled OSError from the auto-create mkdir."""
    blocker = tmp_path / "blocker_file"
    blocker.write_text("x", encoding="utf-8")
    bad_path = blocker / "studio_dir"

    resp = await _post_studio({"name": "Blocked", "path": str(bad_path), "goal": ""})
    assert resp.status_code == 400, resp.text


@pytest.mark.asyncio
async def test_concurrent_duplicate_creates_exactly_one_success(
    _init_ok, tmp_path: Path
) -> None:
    """두 요청이 동시에 같은 신규 경로를 스튜디오로 생성 시도 — 정확히 하나만 201,
    나머지는 409, 레지스트리엔 단일 엔트리만 남아야 한다."""
    studio_dir = tmp_path / "brand_new_concurrent" / "studio_dir"
    assert not studio_dir.exists()

    body_a = {"name": "Racer A", "path": str(studio_dir), "goal": ""}
    body_b = {"name": "Racer B", "path": str(studio_dir), "goal": ""}

    resp_a, resp_b = await asyncio.gather(_post_studio(body_a), _post_studio(body_b))

    statuses = sorted([resp_a.status_code, resp_b.status_code])
    assert statuses == [201, 409], (resp_a.text, resp_b.text)

    studios_resp = await _get_studios()
    assert studios_resp.status_code == 200
    matching = [
        s for s in studios_resp.json() if Path(s["path"]) == studio_dir.resolve()
    ]
    assert len(matching) == 1


class TestDeleteStudio:
    @pytest.mark.asyncio
    async def test_delete_studio_happy_path(self, _init_ok, tmp_path: Path) -> None:
        studio_dir = tmp_path / "studio_to_delete"
        studio_dir.mkdir()

        created = await _post_studio(
            {"name": "Delete Me", "path": str(studio_dir), "goal": ""}
        )
        assert created.status_code == 201, created.text
        studio_id = created.json()["id"]

        resp = await _delete_studio(studio_id)
        assert resp.status_code == 204, resp.text

        studios_resp = await _get_studios()
        assert all(s["id"] != studio_id for s in studios_resp.json())
        # Folder must survive a user-initiated delete (unlike auto-rollback).
        assert studio_dir.is_dir()

    @pytest.mark.asyncio
    async def test_delete_unknown_studio_returns_404(self) -> None:
        resp = await _delete_studio("does-not-exist")
        assert resp.status_code == 404, resp.text

    @pytest.mark.asyncio
    async def test_delete_studio_rejects_project_kind(self, tmp_path: Path) -> None:
        """A registry entry with kind='project' must not be deletable via the
        studios route — it belongs to /v1/projects."""
        registry = app.state.registry
        project_dir = tmp_path / "a_real_project"
        project_dir.mkdir()
        project = await registry.create(name="Real Project", path=str(project_dir))

        resp = await _delete_studio(project.id)
        assert resp.status_code == 404, resp.text


@pytest.mark.asyncio
async def test_run_studio_init_env_defaults_lang_when_absent(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """_run_studio_init 이 spawn 하는 서브프로세스 env 에도 LANG 기본값 fix가
    적용돼야 한다 — forge_runner 뿐 아니라 공용 헬퍼(config.build_forge_subprocess_env)
    를 통해 모든 forge.sh 호출자가 동일하게 공유한다."""
    monkeypatch.delenv("LANG", raising=False)
    monkeypatch.delenv("LC_ALL", raising=False)

    fake_forge_sh = tmp_path / "forge.sh"
    fake_forge_sh.write_text("#!/bin/bash\n", encoding="utf-8")
    monkeypatch.setattr(_studios_mod, "FORGE_SH_PATH", fake_forge_sh)

    captured_env: dict[str, str] = {}

    class _FakeProc:
        returncode = 0

        async def communicate(self) -> tuple[bytes, bytes]:
            return b"", b""

    async def _fake_create_subprocess_exec(*args, **kwargs):  # noqa: ARG001
        captured_env.update(kwargs.get("env", {}))
        return _FakeProc()

    monkeypatch.setattr(
        _studios_mod.asyncio, "create_subprocess_exec", _fake_create_subprocess_exec
    )

    project_dir = tmp_path / "env_check_studio"
    project_dir.mkdir()
    err = await _studios_mod._run_studio_init(project_dir, "EnvCheck", "goal")
    assert err is None
    assert captured_env.get("LANG") == "C.UTF-8"


# ---------------------------------------------------------------------------
# goal field (BACKLOG.md P0-3)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_create_studio_echoes_goal(_init_ok, tmp_path: Path) -> None:
    studio_dir = tmp_path / "studio_goal_echo"
    studio_dir.mkdir()

    resp = await _post_studio(
        {"name": "Goal Echo", "path": str(studio_dir), "goal": "write a novel"}
    )
    assert resp.status_code == 201, resp.text
    assert resp.json()["goal"] == "write a novel"


@pytest.mark.asyncio
async def test_create_studio_goal_defaults_empty_string(_init_ok, tmp_path: Path) -> None:
    studio_dir = tmp_path / "studio_goal_default"
    studio_dir.mkdir()

    resp = await _post_studio({"name": "No Goal", "path": str(studio_dir), "goal": ""})
    assert resp.status_code == 201, resp.text
    assert resp.json()["goal"] == ""


@pytest.mark.asyncio
async def test_list_studios_reads_goal_from_studio_json(_init_ok, tmp_path: Path) -> None:
    """goal in the list response is read from studio.json on disk, not the
    registry — write it manually after create (forge studio init is stubbed
    as a no-op by _init_ok and never actually writes the file)."""
    studio_dir = tmp_path / "studio_goal_from_disk"
    studio_dir.mkdir()

    created = await _post_studio({"name": "From Disk", "path": str(studio_dir), "goal": ""})
    assert created.status_code == 201, created.text

    (studio_dir / "studio.json").write_text(
        json.dumps({"goal": "on-disk goal"}), encoding="utf-8"
    )

    studios_resp = await _get_studios()
    assert studios_resp.status_code == 200
    entry = next(s for s in studios_resp.json() if s["name"] == "From Disk")
    assert entry["goal"] == "on-disk goal"


@pytest.mark.asyncio
async def test_list_studios_goal_empty_when_studio_json_missing(
    _init_ok, tmp_path: Path
) -> None:
    studio_dir = tmp_path / "studio_no_json"
    studio_dir.mkdir()

    created = await _post_studio({"name": "No Json", "path": str(studio_dir), "goal": ""})
    assert created.status_code == 201, created.text
    assert not (studio_dir / "studio.json").exists()

    studios_resp = await _get_studios()
    entry = next(s for s in studios_resp.json() if s["name"] == "No Json")
    assert entry["goal"] == ""


@pytest.mark.asyncio
async def test_list_studios_goal_empty_when_studio_json_corrupt(
    _init_ok, tmp_path: Path
) -> None:
    studio_dir = tmp_path / "studio_corrupt_json"
    studio_dir.mkdir()

    created = await _post_studio({"name": "Corrupt Json", "path": str(studio_dir), "goal": ""})
    assert created.status_code == 201, created.text

    (studio_dir / "studio.json").write_text("{not valid json", encoding="utf-8")

    studios_resp = await _get_studios()
    entry = next(s for s in studios_resp.json() if s["name"] == "Corrupt Json")
    assert entry["goal"] == ""


# ---------------------------------------------------------------------------
# stderr redaction (BACKLOG.md P1)
# ---------------------------------------------------------------------------


class _FakeFailingProc:
    def __init__(self, stderr: bytes, returncode: int = 1) -> None:
        self.returncode = returncode
        self._stderr = stderr

    async def communicate(self) -> tuple[bytes, bytes]:
        return b"", self._stderr


@pytest.mark.asyncio
async def test_run_studio_init_redacts_absolute_paths_and_logs_full_text(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    """The returned error string must not carry the raw absolute path that
    appeared in forge.sh's stderr, but the full text must still be logged."""
    fake_forge_sh = tmp_path / "forge.sh"
    fake_forge_sh.write_text("#!/bin/bash\n", encoding="utf-8")
    monkeypatch.setattr(_studios_mod, "FORGE_SH_PATH", fake_forge_sh)

    raw_stderr = (
        b"some noise on stdout\n"
        rb"C:\Users\secretuser\AppData\Local\golem\forge.sh: line 42: soul-create: command not found"
    )

    async def _fake_create_subprocess_exec(*args, **kwargs):  # noqa: ARG001
        return _FakeFailingProc(raw_stderr)

    monkeypatch.setattr(
        _studios_mod.asyncio, "create_subprocess_exec", _fake_create_subprocess_exec
    )

    project_dir = tmp_path / "redact_check_studio"
    project_dir.mkdir()

    with caplog.at_level(logging.ERROR, logger="golem_gateway.api_studios"):
        err = await _studios_mod._run_studio_init(project_dir, "RedactCheck", "goal")

    assert err is not None
    assert "secretuser" not in err
    assert "C:\\Users" not in err
    assert len(err) <= 200

    # Full raw text (including the secret path) must still be in server logs.
    full_logged = "\n".join(r.getMessage() for r in caplog.records)
    assert "secretuser" in full_logged


# ---------------------------------------------------------------------------
# GET /v1/studio-presets
# ---------------------------------------------------------------------------


async def _get_studio_presets():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        return await client.get("/v1/studio-presets")


def _write_preset(dir_path: Path, filename: str, data: dict | None) -> None:
    dir_path.mkdir(parents=True, exist_ok=True)
    if data is None:
        (dir_path / filename).write_text("{not valid json", encoding="utf-8")
    else:
        (dir_path / filename).write_text(json.dumps(data), encoding="utf-8")


@pytest.mark.asyncio
async def test_list_studio_presets_happy_path(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    presets_dir = tmp_path / "studio-presets"
    _write_preset(
        presets_dir,
        "novel-team.json",
        {"id": "novel-team", "name": "소설팀", "description": "소설 창작 팀", "agents": [], "steps": []},
    )
    _write_preset(
        presets_dir,
        "market-research.json",
        {"id": "market-research", "name": "시장조사팀", "description": "시장조사 팀", "agents": [], "steps": []},
    )
    monkeypatch.setattr(_studios_mod, "_studio_presets_dir", lambda: presets_dir)

    resp = await _get_studio_presets()
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert [p["id"] for p in data] == ["market-research", "novel-team"]
    for p in data:
        assert set(p.keys()) == {"id", "name", "description"}


@pytest.mark.asyncio
async def test_list_studio_presets_skips_corrupt_file(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    presets_dir = tmp_path / "studio-presets"
    _write_preset(
        presets_dir,
        "good.json",
        {"id": "good", "name": "Good", "description": "A valid preset", "agents": [], "steps": []},
    )
    _write_preset(presets_dir, "corrupt.json", None)
    _write_preset(presets_dir, "missing-field.json", {"id": "missing-field", "name": "No Description"})
    monkeypatch.setattr(_studios_mod, "_studio_presets_dir", lambda: presets_dir)

    resp = await _get_studio_presets()
    assert resp.status_code == 200, resp.text
    assert [p["id"] for p in resp.json()] == ["good"]


@pytest.mark.asyncio
async def test_list_studio_presets_missing_dir_returns_empty_list(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setattr(_studios_mod, "_studio_presets_dir", lambda: tmp_path / "does-not-exist")

    resp = await _get_studio_presets()
    assert resp.status_code == 200, resp.text
    assert resp.json() == []


@pytest.mark.asyncio
async def test_list_studio_presets_duplicate_id_keeps_first(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """같은 id 를 선언한 파일이 둘이면 하나만 남는다 (id 는 클라이언트 목록 키)."""
    presets_dir = tmp_path / "studio-presets"
    _write_preset(
        presets_dir,
        "a-dup.json",
        {"id": "dup", "name": "First", "description": "first wins", "agents": [], "steps": []},
    )
    _write_preset(
        presets_dir,
        "b-dup.json",
        {"id": "dup", "name": "Second", "description": "dropped", "agents": [], "steps": []},
    )
    monkeypatch.setattr(_studios_mod, "_studio_presets_dir", lambda: presets_dir)

    resp = await _get_studio_presets()
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert len(data) == 1
    assert data[0]["id"] == "dup"


def test_studio_presets_dir_resolves_from_forge_sh_path() -> None:
    """_studio_presets_dir 실경로 계산 회귀 가드 (모든 목록 테스트가 이를 monkeypatch 하므로)."""
    from golem_gateway.config import FORGE_SH_PATH

    assert _studios_mod._studio_presets_dir() == (
        FORGE_SH_PATH.parent / "templates" / "studio-presets"
    )


@pytest.mark.asyncio
async def test_create_studio_500_detail_has_no_raw_path(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    """End-to-end: a real forge.sh subprocess failure must not leak an
    absolute path through the POST /v1/studios 500 detail."""
    fake_forge_sh = tmp_path / "forge.sh"
    fake_forge_sh.write_text("#!/bin/bash\n", encoding="utf-8")
    monkeypatch.setattr(_studios_mod, "FORGE_SH_PATH", fake_forge_sh)

    raw_stderr = rb"C:\Users\secretuser\AppData\Local\golem\forge.sh: soul-create failed"

    async def _fake_create_subprocess_exec(*args, **kwargs):  # noqa: ARG001
        return _FakeFailingProc(raw_stderr)

    monkeypatch.setattr(
        _studios_mod.asyncio, "create_subprocess_exec", _fake_create_subprocess_exec
    )

    studio_dir = tmp_path / "studio_500_no_leak"
    studio_dir.mkdir()

    with caplog.at_level(logging.ERROR, logger="golem_gateway.api_studios"):
        resp = await _post_studio({"name": "No Leak", "path": str(studio_dir), "goal": ""})

    assert resp.status_code == 500, resp.text
    detail = resp.json()["detail"]
    assert "secretuser" not in detail
    assert "C:\\Users" not in detail

    full_logged = "\n".join(r.getMessage() for r in caplog.records)
    assert "secretuser" in full_logged
