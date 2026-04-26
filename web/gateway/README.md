# GolemGarden Gateway

FastAPI gateway for SOUL metadata, chat sessions, growth-log, forge runner.

## Requirements

- Python 3.13+
- [uv](https://github.com/astral-sh/uv)

## Run

```bash
cd web/gateway

# Install deps (first time)
python -m uv sync

# Start server (127.0.0.1:8642)
python -m uv run python -m golem_gateway.main
```

Or directly with uvicorn after activating the venv:

```bash
.venv/Scripts/activate
uvicorn golem_gateway.main:app --host 127.0.0.1 --port 8642
```

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET  | `/health` | Server liveness |
| GET  | `/v1/souls` | List SOULs (no content) |
| GET  | `/v1/souls/{id}` | Single SOUL with 6 fields (tools, disallowed_tools, max_turns, isolation, is_coordinator, effort) + markdown |
| GET  | `/v1/projects` | Project list / active project state |
| POST | `/v1/runs` | Start a run (SSE) — chat 종료 시 `growth_log.py` 자동 후크 |
| GET  | `/v1/runs/{id}/events` | SSE event stream |
| GET  | `/v1/sessions` / `/v1/sessions/{id}` | Session listing / detail (sessions.db, WAL + auto-migration) |
| GET  | `/v1/activity` | growth-log/achievements/chemistry aggregates |
| GET  | `/v1/board` | forge-board.md 파서 — team/tech_debt/history (마크다운 강조 셀 평탄화) |
| GET  | `/v1/skills/global` | 글로벌 OMC 스킬 카탈로그 |
| POST | `/v1/forge/*` | forge.sh whitelist subprocess runner |

## SOUL discovery

Scans two directories (project override wins):
1. `.golem/souls/*.md` — project-level overrides
2. `souls/*.md` — global fallback

Set `GOLEM_PROJECT` env var to override the project root detection.

## sessions.db

SQLite WAL + per-connection FK. Schema 버전은 `PRAGMA user_version` 으로 자동 마이그레이션 (WAL checkpoint → backup → ALTER → checkpoint). 신규 설치는 latest 로 바로 시작.

## Tests

```bash
uv run pytest                        # 187 케이스
uv run pytest --cov=golem_gateway    # 커버리지 (pytest-cov 필요)
```
