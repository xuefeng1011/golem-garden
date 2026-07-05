"""Tests for GET /v1/projects/{id}/artifacts and /artifacts/content.

Mirrors test_api_flows.py style: bare ASGITransport + a `_prime_app_state`
autouse fixture, and a `registered_project` fixture that monkeypatches
ProjectRegistry.get to return a fake Project without touching the real
registry file.
"""

from __future__ import annotations

import os
from pathlib import Path

import pytest
from httpx import ASGITransport, AsyncClient

from golem_gateway.main import app
from golem_gateway.registry import Project, ProjectRegistry


@pytest.fixture(autouse=True)
def _prime_app_state() -> None:
    """Set app.state.registry if the lifespan hasn't done it yet."""
    if not hasattr(app.state, "registry"):
        app.state.registry = ProjectRegistry()


@pytest.fixture()
def registered_project(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    """Register a temp project and return (project_id, project_path)."""
    from datetime import datetime, timezone

    project_path = tmp_path / "test_project"
    project_path.mkdir()

    fake_project = Project(
        id="proj-artifacts",
        name="Artifacts Test Project",
        path=str(project_path),
        created_at=datetime.now(tz=timezone.utc).isoformat(),
    )

    async def fake_get(self_or_project_id, project_id: str | None = None):
        pid = project_id if project_id is not None else self_or_project_id
        if pid == "proj-artifacts":
            return fake_project
        return None

    monkeypatch.setattr(ProjectRegistry, "get", fake_get)
    return ("proj-artifacts", project_path)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


async def _list(project_id: str, params: dict | None = None):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        return await client.get(f"/v1/projects/{project_id}/artifacts", params=params or {})


async def _content(project_id: str, params: dict):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        return await client.get(f"/v1/projects/{project_id}/artifacts/content", params=params)


# ---------------------------------------------------------------------------
# List tests
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_list_empty_dir_returns_empty_list(registered_project) -> None:
    project_id, _ = registered_project
    resp = await _list(project_id, {"dir": "output"})
    assert resp.status_code == 200
    assert resp.json() == []


@pytest.mark.asyncio
async def test_list_defaults_dir_to_output(registered_project) -> None:
    project_id, project_path = registered_project
    out = project_path / "output"
    out.mkdir()
    (out / "a.txt").write_text("hello", encoding="utf-8")

    resp = await _list(project_id)
    assert resp.status_code == 200
    data = resp.json()
    assert len(data) == 1
    assert data[0]["path"] == "output/a.txt"


@pytest.mark.asyncio
async def test_list_happy_path_nested_sorted_and_fields(registered_project) -> None:
    project_id, project_path = registered_project
    out = project_path / "output"
    out.mkdir()
    (out / "old.txt").write_text("old", encoding="utf-8")
    nested = out / "sub"
    nested.mkdir()
    (nested / "new.txt").write_text("newer content", encoding="utf-8")

    # Make "new.txt" newer than "old.txt".
    old_path = out / "old.txt"
    new_path = nested / "new.txt"
    old_time = new_path.stat().st_mtime - 100
    os.utime(old_path, (old_time, old_time))

    resp = await _list(project_id, {"dir": "output"})
    assert resp.status_code == 200
    data = resp.json()
    assert len(data) == 2
    # Newest first.
    assert data[0]["path"] == "output/sub/new.txt"
    assert data[0]["name"] == "new.txt"
    assert data[0]["size"] == len("newer content")
    assert "mtime" in data[0] and data[0]["mtime"]
    assert data[1]["path"] == "output/old.txt"


@pytest.mark.asyncio
async def test_list_skips_dotfiles_and_dotdirs(registered_project) -> None:
    project_id, project_path = registered_project
    out = project_path / "output"
    out.mkdir()
    (out / ".hidden.txt").write_text("x", encoding="utf-8")
    dotdir = out / ".git"
    dotdir.mkdir()
    (dotdir / "config").write_text("x", encoding="utf-8")
    (out / "visible.txt").write_text("x", encoding="utf-8")

    resp = await _list(project_id, {"dir": "output"})
    assert resp.status_code == 200
    paths = [e["path"] for e in resp.json()]
    assert paths == ["output/visible.txt"]


@pytest.mark.asyncio
async def test_list_nonexistent_dir_returns_empty_not_404(registered_project) -> None:
    project_id, _ = registered_project
    resp = await _list(project_id, {"dir": "no_such_dir"})
    assert resp.status_code == 200
    assert resp.json() == []


@pytest.mark.asyncio
async def test_list_unknown_project_404() -> None:
    resp = await _list("nope")
    assert resp.status_code == 404


@pytest.mark.parametrize(
    "bad_dir",
    [
        "../escape",
        "output/../../escape",
        "/absolute/path",
        "C:/absolute/path",
        "output\\backslash",
    ],
)
@pytest.mark.asyncio
async def test_list_traversal_attempts_return_400(registered_project, bad_dir: str) -> None:
    project_id, _ = registered_project
    resp = await _list(project_id, {"dir": bad_dir})
    assert resp.status_code == 400, resp.text


@pytest.mark.asyncio
async def test_list_symlink_escape_returns_400(registered_project, tmp_path: Path) -> None:
    project_id, project_path = registered_project
    outside = tmp_path / "outside_secret"
    outside.mkdir()
    (outside / "secret.txt").write_text("nope", encoding="utf-8")

    link = project_path / "escape_link"
    try:
        link.symlink_to(outside, target_is_directory=True)
    except (OSError, NotImplementedError):
        pytest.skip("symlinks not supported in this environment")

    resp = await _list(project_id, {"dir": "escape_link"})
    assert resp.status_code == 400, resp.text


@pytest.mark.asyncio
async def test_list_nested_symlink_dir_escape_skipped_no_500(
    registered_project, tmp_path: Path
) -> None:
    """A symlink SUBDIRECTORY nested under an otherwise-valid `dir` (not the
    `dir` itself) must be skipped during the walk, not crash the request."""
    project_id, project_path = registered_project
    outside = tmp_path / "outside_nested_dir"
    outside.mkdir()
    (outside / "secret.txt").write_text("nope", encoding="utf-8")

    out = project_path / "output"
    out.mkdir()
    (out / "visible.txt").write_text("x", encoding="utf-8")

    nested_link = out / "sub_link"
    try:
        nested_link.symlink_to(outside, target_is_directory=True)
    except (OSError, NotImplementedError):
        pytest.skip("symlinks not supported in this environment")

    resp = await _list(project_id, {"dir": "output"})
    assert resp.status_code == 200, resp.text
    paths = [e["path"] for e in resp.json()]
    assert paths == ["output/visible.txt"]


@pytest.mark.asyncio
async def test_list_nested_symlink_file_escape_skipped_no_500(
    registered_project, tmp_path: Path
) -> None:
    """A symlink FILE nested under an otherwise-valid `dir` must be skipped
    during the walk, not crash the request."""
    project_id, project_path = registered_project
    outside_file = tmp_path / "outside_secret_file.txt"
    outside_file.write_text("nope", encoding="utf-8")

    out = project_path / "output"
    out.mkdir()
    (out / "visible.txt").write_text("x", encoding="utf-8")

    link_file = out / "linked_file.txt"
    try:
        link_file.symlink_to(outside_file)
    except (OSError, NotImplementedError):
        pytest.skip("symlinks not supported in this environment")

    resp = await _list(project_id, {"dir": "output"})
    assert resp.status_code == 200, resp.text
    paths = [e["path"] for e in resp.json()]
    assert paths == ["output/visible.txt"]


# ---------------------------------------------------------------------------
# Content tests
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_content_happy_path(registered_project) -> None:
    project_id, project_path = registered_project
    out = project_path / "output"
    out.mkdir()
    # write_bytes (not write_text) avoids platform newline translation so the
    # on-disk bytes match the assertion exactly.
    (out / "report.md").write_bytes("# Report\nhello".encode("utf-8"))

    resp = await _content(project_id, {"path": "output/report.md"})
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["path"] == "output/report.md"
    assert data["content"] == "# Report\nhello"
    assert data["truncated"] is False
    assert data["binary"] is False
    assert data["size"] == len("# Report\nhello".encode("utf-8"))


@pytest.mark.asyncio
async def test_content_path_is_project_relative_not_under_dir(registered_project) -> None:
    """content's `path` is project-relative, independent of any `dir` param —
    a file directly under the project root (not inside output/) is fine."""
    project_id, project_path = registered_project
    (project_path / "root_note.txt").write_text("top level", encoding="utf-8")

    resp = await _content(project_id, {"path": "root_note.txt"})
    assert resp.status_code == 200, resp.text
    assert resp.json()["content"] == "top level"


@pytest.mark.asyncio
async def test_content_truncation_beyond_cap(registered_project) -> None:
    project_id, project_path = registered_project
    out = project_path / "output"
    out.mkdir()
    big = "x" * (256 * 1024 + 100)
    (out / "big.txt").write_text(big, encoding="utf-8")

    resp = await _content(project_id, {"path": "output/big.txt"})
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["truncated"] is True
    assert len(data["content"]) == 256 * 1024
    assert data["size"] == len(big)


@pytest.mark.asyncio
async def test_content_binary_detection(registered_project) -> None:
    project_id, project_path = registered_project
    out = project_path / "output"
    out.mkdir()
    (out / "blob.bin").write_bytes(b"abc\x00def")

    resp = await _content(project_id, {"path": "output/blob.bin"})
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["binary"] is True
    assert data["content"] == ""
    assert data["size"] == 7


@pytest.mark.asyncio
async def test_content_unknown_file_returns_404(registered_project) -> None:
    project_id, _ = registered_project
    resp = await _content(project_id, {"path": "output/nope.txt"})
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_content_unknown_project_404() -> None:
    resp = await _content("nope", {"path": "output/a.txt"})
    assert resp.status_code == 404


@pytest.mark.parametrize(
    "bad_path",
    [
        "../escape.txt",
        "output/../../escape.txt",
        "/absolute.txt",
        "C:/absolute.txt",
        "output\\backslash.txt",
    ],
)
@pytest.mark.asyncio
async def test_content_traversal_attempts_return_400(registered_project, bad_path: str) -> None:
    project_id, _ = registered_project
    resp = await _content(project_id, {"path": bad_path})
    assert resp.status_code == 400, resp.text


@pytest.mark.asyncio
async def test_content_directory_path_returns_404(registered_project) -> None:
    """A path that resolves to a directory (not a file) is not found, not a 500."""
    project_id, project_path = registered_project
    out = project_path / "output"
    out.mkdir()

    resp = await _content(project_id, {"path": "output"})
    assert resp.status_code == 404
