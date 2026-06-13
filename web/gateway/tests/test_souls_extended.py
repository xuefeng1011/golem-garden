"""Tests for SoulDetail extended fields (N3 — tools/disallowed_tools/max_turns/isolation/is_coordinator/effort).

Bash 정합성: soul-parser.sh:112-152 로직을 Python으로 미러링했는지 검증.
API 직렬화: GET /v1/projects/{id}/souls/{soul_id} 응답이 새 필드를 모두 포함하는지 검증.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from golem_gateway.souls import (
    _COORDINATOR_DISALLOWED_TOOLS,
    _COORDINATOR_TOOLS,
    _RANK_DEFAULT_MAX_TURNS,
    _RANK_DEFAULT_TOOLS,
    _parse_soul_file,
    _parse_tools_field,
    _resolve_disallowed_tools,
    _resolve_effort,
    _resolve_isolation,
    _resolve_max_turns,
    _resolve_tools,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _write_soul(path: Path, **fields) -> Path:
    """frontmatter + body를 가진 최소 SOUL 파일 작성."""
    lines = ["---"]
    for k, v in fields.items():
        if isinstance(v, list):
            items = ", ".join(v)
            lines.append(f"{k}: [{items}]")
        else:
            lines.append(f"{k}: {v}")
    lines += ["---", "", "본문 내용입니다."]
    path.write_text("\n".join(lines), encoding="utf-8")
    return path


# ---------------------------------------------------------------------------
# 1. _parse_tools_field — csv / yaml list 모두 처리
# ---------------------------------------------------------------------------

class TestParseToolsField:
    def test_yaml_list(self):
        assert _parse_tools_field(["Read", "Write"]) == ["Read", "Write"]

    def test_csv_string(self):
        assert _parse_tools_field("Read, Write, Bash") == ["Read", "Write", "Bash"]

    def test_none_returns_empty(self):
        assert _parse_tools_field(None) == []

    def test_single_string(self):
        assert _parse_tools_field("Read") == ["Read"]

    def test_strips_whitespace(self):
        assert _parse_tools_field("  Read , Edit  ") == ["Read", "Edit"]


# ---------------------------------------------------------------------------
# 2. frontmatter 직접 명시 케이스
# ---------------------------------------------------------------------------

class TestFrontmatterExplicitTools:
    def test_yaml_list_tools(self, tmp_path: Path):
        md = _write_soul(
            tmp_path / "ryn.md",
            name="Ryn", role="backend-developer", rank="junior",
            model="sonnet", tools=["Read", "Write"],
        )
        soul = _parse_soul_file(md)
        assert soul is not None
        assert soul.tools == ["Read", "Write"]

    def test_disallowed_tools_exposed(self, tmp_path: Path):
        md = _write_soul(
            tmp_path / "custom.md",
            name="Custom", role="backend-developer", rank="junior",
            model="sonnet",
        )
        # disallowed_tools는 non-director에겐 빈 목록
        soul = _parse_soul_file(md)
        assert soul is not None
        assert soul.disallowed_tools == []

    def test_camel_case_max_turns_mapping(self, tmp_path: Path):
        """frontmatter maxTurns → field max_turns (camelCase → snake_case)."""
        content = "---\nname: Test\nrole: backend-developer\nrank: junior\nmodel: sonnet\nmaxTurns: 30\n---\n\n본문"
        md = tmp_path / "test.md"
        md.write_text(content, encoding="utf-8")
        soul = _parse_soul_file(md)
        assert soul is not None
        assert soul.max_turns == 30

    def test_isolation_frontmatter_worktree(self, tmp_path: Path):
        content = "---\nname: Test\nrole: backend-developer\nrank: senior\nmodel: sonnet\nisolation: worktree\n---\n\n본문"
        md = tmp_path / "test.md"
        md.write_text(content, encoding="utf-8")
        soul = _parse_soul_file(md)
        assert soul is not None
        assert soul.isolation == "worktree"

    def test_effort_frontmatter_low(self, tmp_path: Path):
        content = "---\nname: Test\nrole: qa-tester\nrank: novice\nmodel: haiku\neffort: low\n---\n\n본문"
        md = tmp_path / "test.md"
        md.write_text(content, encoding="utf-8")
        soul = _parse_soul_file(md)
        assert soul is not None
        assert soul.effort == "low"


# ---------------------------------------------------------------------------
# 3. rank 기본값 fallback — soul-parser.sh:113-120 정합성
# ---------------------------------------------------------------------------

class TestRankDefaultFallback:
    @pytest.mark.parametrize("rank,expected_tools", [
        ("novice", _RANK_DEFAULT_TOOLS["novice"]),
        ("junior", _RANK_DEFAULT_TOOLS["junior"]),
        ("senior", _RANK_DEFAULT_TOOLS["senior"]),
        ("lead",   _RANK_DEFAULT_TOOLS["lead"]),
        ("master", _RANK_DEFAULT_TOOLS["master"]),
    ])
    def test_rank_tools_default(self, rank: str, expected_tools: list[str], tmp_path: Path):
        content = f"---\nname: T\nrole: backend-developer\nrank: {rank}\nmodel: sonnet\n---\n\n본문"
        md = tmp_path / "t.md"
        md.write_text(content, encoding="utf-8")
        soul = _parse_soul_file(md)
        assert soul is not None
        assert soul.tools == expected_tools

    @pytest.mark.parametrize("rank,expected_turns", [
        ("novice", 15), ("junior", 25), ("senior", 40), ("lead", 60), ("master", 80),
    ])
    def test_rank_max_turns_default(self, rank: str, expected_turns: int, tmp_path: Path):
        content = f"---\nname: T\nrole: backend-developer\nrank: {rank}\nmodel: sonnet\n---\n\n본문"
        md = tmp_path / "t.md"
        md.write_text(content, encoding="utf-8")
        soul = _parse_soul_file(md)
        assert soul is not None
        assert soul.max_turns == expected_turns

    def test_novice_tools_without_frontmatter(self, tmp_path: Path):
        """tools 미명시 novice → soul-parser.sh novice 기본값과 동일."""
        content = "---\nname: Zen\nrole: qa-tester\nrank: novice\nmodel: haiku\n---\n\n본문"
        md = tmp_path / "zen.md"
        md.write_text(content, encoding="utf-8")
        soul = _parse_soul_file(md)
        assert soul is not None
        # qa-tester는 director가 아니므로 rank 기본값 적용
        assert soul.tools == _RANK_DEFAULT_TOOLS["novice"]
        assert soul.max_turns == 15


# ---------------------------------------------------------------------------
# 4. Director 격리 — soul-parser.sh:126-133 정합성
# ---------------------------------------------------------------------------

class TestDirectorIsolation:
    def test_director_tools_forced(self, tmp_path: Path):
        """nex.md: role=director → frontmatter tools 무시, coordinator 도구 강제."""
        content = (
            "---\n"
            "name: Nex\nrole: director\nrank: junior\nmodel: opus\n"
            "tools: [Read, Edit, Write]  # 이게 무시돼야 함\n"
            "---\n\n본문"
        )
        md = tmp_path / "nex.md"
        md.write_text(content, encoding="utf-8")
        soul = _parse_soul_file(md)
        assert soul is not None
        assert soul.tools == list(_COORDINATOR_TOOLS)
        assert "Edit" not in soul.tools
        assert "Write" not in soul.tools
        assert "Bash" not in soul.tools

    def test_director_disallowed_tools_forced(self, tmp_path: Path):
        """director → disallowed_tools 강제 (Edit/Write/Bash 포함)."""
        content = "---\nname: Nex\nrole: director\nrank: junior\nmodel: opus\n---\n\n본문"
        md = tmp_path / "nex.md"
        md.write_text(content, encoding="utf-8")
        soul = _parse_soul_file(md)
        assert soul is not None
        assert soul.disallowed_tools == list(_COORDINATOR_DISALLOWED_TOOLS)
        assert "Edit" in soul.disallowed_tools
        assert "Write" in soul.disallowed_tools
        assert "Bash" in soul.disallowed_tools

    def test_director_is_coordinator_true(self, tmp_path: Path):
        """role=director → is_coordinator=True (frontmatter 미명시도)."""
        content = "---\nname: Nex\nrole: director\nrank: junior\nmodel: opus\n---\n\n본문"
        md = tmp_path / "nex.md"
        md.write_text(content, encoding="utf-8")
        soul = _parse_soul_file(md)
        assert soul is not None
        assert soul.is_coordinator is True

    def test_is_coordinator_explicit_true(self, tmp_path: Path):
        """is_coordinator: true frontmatter → coordinator 도구 강제 (role 무관)."""
        content = "---\nname: X\nrole: backend-developer\nrank: senior\nmodel: sonnet\nis_coordinator: true\n---\n\n본문"
        md = tmp_path / "x.md"
        md.write_text(content, encoding="utf-8")
        soul = _parse_soul_file(md)
        assert soul is not None
        assert soul.is_coordinator is True
        assert soul.tools == list(_COORDINATOR_TOOLS)

    def test_director_max_turns_50(self, tmp_path: Path):
        """director max_turns 기본값 = 50 (soul-parser.sh:139)."""
        content = "---\nname: Nex\nrole: director\nrank: junior\nmodel: opus\n---\n\n본문"
        md = tmp_path / "nex.md"
        md.write_text(content, encoding="utf-8")
        soul = _parse_soul_file(md)
        assert soul is not None
        assert soul.max_turns == 50

    def test_director_isolation_none(self, tmp_path: Path):
        """director isolation = none (soul-parser.sh:146)."""
        content = "---\nname: Nex\nrole: director\nrank: senior\nmodel: opus\n---\n\n본문"
        md = tmp_path / "nex.md"
        md.write_text(content, encoding="utf-8")
        soul = _parse_soul_file(md)
        assert soul is not None
        assert soul.isolation == "none"


# ---------------------------------------------------------------------------
# 5. isolation 기본값 — rank/role 조합
# ---------------------------------------------------------------------------

class TestIsolationDefaults:
    @pytest.mark.parametrize("rank,role,expected", [
        ("novice", "qa-tester", "none"),
        ("junior", "backend-developer", "none"),
        ("senior", "backend-developer", "worktree"),
        ("lead", "backend-developer", "worktree"),
        ("master", "backend-developer", "worktree"),
    ])
    def test_isolation_by_rank_role(self, rank: str, role: str, expected: str, tmp_path: Path):
        content = f"---\nname: T\nrole: {role}\nrank: {rank}\nmodel: sonnet\n---\n\n본문"
        md = tmp_path / "t.md"
        md.write_text(content, encoding="utf-8")
        soul = _parse_soul_file(md)
        assert soul is not None
        assert soul.isolation == expected


# ---------------------------------------------------------------------------
# 6. effort 기본값 — model 기반
# ---------------------------------------------------------------------------

class TestEffortDefaults:
    @pytest.mark.parametrize("model,expected", [
        ("haiku", "low"),
        ("sonnet", "medium"),
        ("opus", "high"),
        ("claude-sonnet-4-6", "medium"),
        ("claude-haiku-3", "low"),
        ("claude-opus-4", "high"),
        ("unknown-model", "medium"),
    ])
    def test_effort_by_model(self, model: str, expected: str, tmp_path: Path):
        content = f"---\nname: T\nrole: backend-developer\nrank: junior\nmodel: {model}\n---\n\n본문"
        md = tmp_path / "t.md"
        md.write_text(content, encoding="utf-8")
        soul = _parse_soul_file(md)
        assert soul is not None
        assert soul.effort == expected


# ---------------------------------------------------------------------------
# 7. 실제 SOUL 파일 통합 테스트 (nex.md, ryn.md, zen.md)
# ---------------------------------------------------------------------------

class TestRealSoulFiles:
    _GOLEM_DIR = Path("C:/01_xuefeng/08_ai/golem-garden/.golem/souls")
    _GLOBAL_DIR = Path("C:/01_xuefeng/08_ai/golem-garden/souls")

    def _get_soul_path(self, name: str) -> Path | None:
        for d in (self._GOLEM_DIR, self._GLOBAL_DIR):
            p = d / f"{name}.md"
            if p.exists():
                return p
        return None

    def test_nex_coordinator_fields(self):
        path = self._get_soul_path("nex")
        if path is None:
            pytest.skip("nex.md not found")
        soul = _parse_soul_file(path)
        assert soul is not None
        assert soul.is_coordinator is True
        assert soul.tools == list(_COORDINATOR_TOOLS)
        assert "Edit" not in soul.tools
        assert soul.disallowed_tools == list(_COORDINATOR_DISALLOWED_TOOLS)

    def test_ryn_junior_defaults(self):
        path = self._get_soul_path("ryn")
        if path is None:
            pytest.skip("ryn.md not found")
        soul = _parse_soul_file(path)
        assert soul is not None
        assert soul.is_coordinator is False
        # ryn.md에 tools 명시됨 — frontmatter 값 우선
        assert "Read" in soul.tools
        assert soul.max_turns == 25  # junior 기본값 or frontmatter

    def test_zen_novice_defaults(self):
        path = self._get_soul_path("zen")
        if path is None:
            pytest.skip("zen.md not found")
        soul = _parse_soul_file(path)
        assert soul is not None
        assert soul.is_coordinator is False
        assert soul.max_turns == 15  # novice 기본값 or frontmatter
        assert soul.isolation == "none"  # qa-tester


# ---------------------------------------------------------------------------
# 8. JSON 직렬화 — 6개 필드 모두 포함
# ---------------------------------------------------------------------------

class TestJsonSerialization:
    def test_all_new_fields_in_json(self, tmp_path: Path):
        """SoulDetail.model_dump()에 6개 신규 필드 모두 포함되는지 검증."""
        content = (
            "---\n"
            "name: Test\nrole: backend-developer\nrank: junior\nmodel: sonnet\n"
            "tools: [Read, Write]\nmaxTurns: 30\nisolation: none\neffort: medium\n"
            "---\n\n본문"
        )
        md = tmp_path / "test.md"
        md.write_text(content, encoding="utf-8")
        soul = _parse_soul_file(md)
        assert soul is not None

        data = json.loads(soul.model_dump_json())
        assert "tools" in data
        assert "disallowed_tools" in data
        assert "max_turns" in data
        assert "isolation" in data
        assert "is_coordinator" in data
        assert "effort" in data

        assert data["tools"] == ["Read", "Write"]
        assert data["max_turns"] == 30
        assert data["isolation"] == "none"
        assert data["effort"] == "medium"
        assert data["is_coordinator"] is False

    def test_existing_fields_preserved(self, tmp_path: Path):
        """기존 필드(id, name, rank, specialty, description, content)가 누락되지 않음."""
        content = (
            "---\n"
            "name: Test\nrole: backend-developer\nrank: junior\nmodel: sonnet\n"
            "specialty: [python, fastapi]\n"
            "---\n\n첫 번째 본문 줄입니다."
        )
        md = tmp_path / "test.md"
        md.write_text(content, encoding="utf-8")
        soul = _parse_soul_file(md)
        assert soul is not None

        data = json.loads(soul.model_dump_json())
        for field in ("id", "name", "rank", "specialty", "description", "content"):
            assert field in data, f"기존 필드 누락: {field}"
        assert data["name"] == "Test"
        assert data["rank"] == "junior"
        assert "python" in data["specialty"]


# ---------------------------------------------------------------------------
# 9. API 엔드포인트 통합 — GET /v1/projects/{id}/souls/{soul_id}
# ---------------------------------------------------------------------------

def _make_project(tmp_path: Path, soul_content: str, soul_name: str = "testsoul") -> Path:
    """테스트용 프로젝트 구조 생성."""
    souls_dir = tmp_path / "souls"
    souls_dir.mkdir()
    (souls_dir / f"{soul_name}.md").write_text(soul_content, encoding="utf-8")
    (tmp_path / ".golem").mkdir()
    return tmp_path


def _patch_app_state() -> None:
    """app.state에 registry 주입 — lifespan 없이 API 테스트 가능하게."""
    from golem_gateway.forge_runner import ForgeRunner
    from golem_gateway.main import app
    from golem_gateway.registry import ProjectRegistry
    from golem_gateway.session_manager import SessionManager

    if not hasattr(app.state, "session_manager"):
        app.state.session_manager = SessionManager()
    if not hasattr(app.state, "forge_runner"):
        app.state.forge_runner = ForgeRunner()
    if not hasattr(app.state, "registry"):
        app.state.registry = ProjectRegistry()


@pytest.mark.asyncio
async def test_api_soul_detail_includes_new_fields(tmp_path: Path):
    """GET /v1/projects/{id}/souls/testsoul → 6개 신규 필드 직렬화 확인."""
    from golem_gateway.main import app

    _patch_app_state()

    soul_content = (
        "---\n"
        "name: TestSoul\nrole: backend-developer\nrank: junior\nmodel: sonnet\n"
        "tools: [Read, Edit]\nmaxTurns: 20\nisolation: none\neffort: medium\n"
        "---\n\n테스트 SOUL 본문."
    )
    project_path = _make_project(tmp_path, soul_content)

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post("/v1/projects", json={"name": "test-project", "path": str(project_path)})
        assert resp.status_code in (200, 201), resp.text
        project_id = resp.json()["id"]

        resp = await client.get(f"/v1/projects/{project_id}/souls/testsoul")
        assert resp.status_code == 200, resp.text
        data = resp.json()

    for field in ("tools", "disallowed_tools", "max_turns", "isolation", "is_coordinator", "effort"):
        assert field in data, f"API 응답에 신규 필드 누락: {field}"

    assert data["tools"] == ["Read", "Edit"]
    assert data["max_turns"] == 20
    assert data["isolation"] == "none"
    assert data["effort"] == "medium"
    assert data["is_coordinator"] is False
    assert data["disallowed_tools"] == []


@pytest.mark.asyncio
async def test_api_director_soul_coordinator_fields(tmp_path: Path):
    """GET /v1/.../souls/nex → director는 coordinator 도구 강제."""
    from golem_gateway.main import app

    _patch_app_state()

    soul_content = (
        "---\n"
        "name: Nex\nrole: director\nrank: junior\nmodel: opus\n"
        "---\n\n디렉터 본문."
    )
    souls_dir = tmp_path / "souls"
    souls_dir.mkdir()
    (souls_dir / "nex.md").write_text(soul_content, encoding="utf-8")
    (tmp_path / ".golem").mkdir()

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post("/v1/projects", json={"name": "test-director", "path": str(tmp_path)})
        assert resp.status_code in (200, 201)
        project_id = resp.json()["id"]

        resp = await client.get(f"/v1/projects/{project_id}/souls/nex")
        assert resp.status_code == 200
        data = resp.json()

    assert data["is_coordinator"] is True
    assert data["tools"] == list(_COORDINATOR_TOOLS)
    assert "Edit" not in data["tools"]
    assert data["disallowed_tools"] == list(_COORDINATOR_DISALLOWED_TOOLS)


@pytest.mark.asyncio
async def test_api_list_souls_exposes_is_coordinator(tmp_path: Path):
    """GET /v1/.../souls (목록) 도 is_coordinator 노출 — 편집기 Director 경고용."""
    from golem_gateway.main import app

    _patch_app_state()

    souls_dir = tmp_path / "souls"
    souls_dir.mkdir()
    (souls_dir / "nex.md").write_text(
        "---\nname: Nex\nrole: director\nrank: junior\nmodel: opus\n---\n\n디렉터.",
        encoding="utf-8",
    )
    (souls_dir / "ryn.md").write_text(
        "---\nname: Ryn\nrole: backend-developer\nrank: senior\nmodel: sonnet\n---\n\n백엔드.",
        encoding="utf-8",
    )
    (tmp_path / ".golem").mkdir()

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post("/v1/projects", json={"name": "test-list-coord", "path": str(tmp_path)})
        assert resp.status_code in (200, 201)
        project_id = resp.json()["id"]

        resp = await client.get(f"/v1/projects/{project_id}/souls")
        assert resp.status_code == 200, resp.text
        by_id = {s["id"]: s for s in resp.json()}

    assert "is_coordinator" in by_id["nex"], "목록 응답에 is_coordinator 누락"
    assert by_id["nex"]["is_coordinator"] is True
    assert by_id["ryn"]["is_coordinator"] is False
