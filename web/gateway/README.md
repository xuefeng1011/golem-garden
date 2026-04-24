# GolemGarden Gateway

Read-only FastAPI gateway for SOUL metadata. Phase 1 skeleton.

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
| GET | `/health` | Server liveness check |
| GET | `/v1/souls` | List all SOULs (no content body) |
| GET | `/v1/souls/{id}` | Single SOUL with full markdown content |

## SOUL discovery

Scans two directories (project override wins):
1. `.golem/souls/*.md` — project-level overrides
2. `souls/*.md` — global fallback

Set `GOLEM_PROJECT` env var to override the project root detection.

## Phase 2 notes

- Replace `uvicorn.run()` with a lifespan context (`@asynccontextmanager`) when adding the subprocess session manager.
- `/v1/runs` + SSE endpoints go in a new `api_runs.py` router.
