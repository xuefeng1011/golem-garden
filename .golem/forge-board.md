---
project: golem-garden
type: 3-tier 하이브리드 — Bash CLI + Python FastAPI Gateway + Vue 3 Web UI
created: 2026-04-06
updated: 2026-04-25
branch: feature/web-ui (Tier C 진행 중)
---

# Forge Board

## 팀 구성

| SOUL | 역할 | OMC Agent | 모델 | Rank | 상태 | 주력 영역 |
|------|------|-----------|------|------|------|----------|
| **Nex** | Director | architect | opus | junior | active | 팀 빌드/분배, 아키텍처 |
| **Ryn** | Backend (Bash + Python) | executor | sonnet | **junior** | active | lib/, web/gateway/, forge.sh |
| **Kai** | Frontend (Vue/TS) | executor | sonnet | novice | active | web/client/, Pinia, SoulHandoffCard |
| **Zen** | QA Tester | test-engineer | haiku | novice | active | pytest 90개, vitest, 크로스 리뷰 |
| **Bolt** | DevOps | executor | sonnet | novice | active | install.sh, hook, uv/Vite |
| **Sage** | Auditor | code-reviewer | opus | - | standby | 지식 승격 심사 |

> 4/25 갱신: Kai 정식 등록 (이전에 growth-log/achievements 활동만 있었음).
> Ryn은 Tier B에서 streak_10 달성 + tasks_10 등 업적 다수.

## 기술스택 (3-Tier)

### Tier 1: Bash CLI 코어
- forge.sh (1,052줄) + lib/ 30개 모듈 (7,784줄)
- POSIX 호환, `_sed_i()` 래퍼 (macOS/Linux/Windows Git Bash)
- 데이터: JSONL (grep/sed 파싱), YAML frontmatter + Markdown
- soul-parser → growth-log → rank-system → prompt-builder → error-recovery 의존 그래프

### Tier 2: Python FastAPI Gateway
- web/gateway/ — 19 모듈 / 4,753줄
- FastAPI ≥0.136, uvicorn ≥0.46, Pydantic ≥2.13, sse-starlette ≥2.0
- Python ≥3.13, uv 빌드, pytest ≥8.0
- SQLite (sessions.db, WAL mode, open-per-call)
- 데이터 writer: sessions.db, projects.json (atomic write)
- 데이터 reader: growth-log/*.jsonl, mailbox/*.jsonl, achievements.jsonl

### Tier 3: Vue 3 웹 UI
- web/client/ — 44 컴포넌트 / 12 페이지
- Vue 3.5 + Pinia 3 + Vite 8 + vue-router 4
- Naive UI 2.44 + @vicons/ionicons5
- vue-i18n 11 (en/ko), markdown-it 14 + highlight.js 11
- TypeScript ~6.0, vue-tsc 3.2, Sass 1.99
- 테스트: Vitest 3.2 + @vue/test-utils

### 인프라
- install.sh (226줄) — `~/.claude/golem-garden/` + `~/.claude/skills/golem-garden/` 글로벌 설치
- Hook 시스템: auto-dashboard-refresh, auto-growth-log, guard-novice, guard-mailbox, guard-growth-log
- CI/CD: 없음 (로컬 개발 중심, pytest/vitest 수동 실행)

## OMC 실행 모드 설정

| 작업 유형 | 실행 모드 | 설명 |
|----------|----------|------|
| 대규모 빌드 | ultrapilot | SOUL별 병렬 실행 |
| 단순 태스크 | autopilot | 단일 SOUL 자율 실행 |
| 비용 절약 | ecomode | haiku 기반 경량 실행 |
| 리뷰 포함 | pipeline | 작업 → 리뷰 순차 실행 |

## 분배 규칙

- **자동 분배**: Nex(Director)가 태스크 분석 → specialty 매칭 → 배정
- **수동 지정**: `forge assign {soul}: {task}`
- lib/ 모듈 / forge.sh / web/gateway 백엔드 → **Ryn**
- web/client / Vue 컴포넌트 / Pinia store → **Kai**
- pytest / vitest / 크로스 리뷰 → **Zen**
- install.sh / hook / uv / Vite / portability → **Bolt**
- 아키텍처 결정 / 부채 식별 → **Nex** (분배 후)
- 지식 승격 심사 → **Sage** (forge sync 시 호출)

## 기술 부채 추적 (4/25 갱신)

### 4/18 부채 추적

1. ~~JSONL 인젝션~~ — **부분 해결** (`_json_escape()` 적용, 일부 경로 미완)
2. ~~승급 로직 중복~~ — **해결** (`rank_should_promote()` 통합)
3. ~~무조건 모듈 로딩~~ — **해결** (`_load()` lazy loader)
4. **soul_parse() 글로벌 변수 오염** — 미해결 (4/18부터 누적, save/restore 패턴으로 우회)
5. ~~경로 순회 미검증~~ — registry는 해결 (`$HOME` 강제), 모듈별 basename 가드는 재검토 필요

### 4/25 신규 부채 (Tier B/C 도입 후)

| # | 부채 | 우선순위 | 위치 |
|---|------|---------|------|
| **N1** | **데이터 정합성 비대칭** — Gateway는 sessions.db에만, Bash는 growth-log/jsonl에만 쓴다. **chat에서 자동 승급이 트리거되지 않음** | **HIGH** | api_runs.py:191-216 ↔ growth-log.sh:51 |
| **N2** | **schema_version 마이그레이션 미구현** — `CURRENT_SCHEMA_VERSION=1` 고정, ALTER 분기 부재 | **HIGH** | sessions_db.py:121-126 |
| N3 | SOUL 정의 3중 노출 비대칭 — Pydantic SoulDetail이 tools/maxTurns/disallowed_tools 미노출 | MEDIUM | souls.py:15-28 |
| N4 | **Bash 단위 테스트 부재** — Python 90개 vs Bash 0개. forge.sh + lib/ ~9.9K LOC가 회귀 검출 수단 없음 | MEDIUM | tests/bats/ 신규 필요 |
| N5 | `_VALID_SKILL_ID` symlink 회피 가정 — single-user localhost 한정 | LOW | skills.py:144-149 |
| N6 | forge.sh 내부 escape — eval/변수확장 사용. 새 subcommand 추가 시 회귀 위험 | LOW | forge.sh:48 |

> Root cause: **두 데이터 writer의 lifecycle event가 통합되지 않음**. 자세한 분석은 `.golem/analysis.md` 참조.

## 태스크 히스토리

| 날짜 | 태스크 | 담당 SOUL | 결과 | 비고 |
|------|--------|----------|------|------|
| 2026-04-06 | forge-init | - | success | 프로젝트 초기화 |
| 2026-04-06 | 기술부채 전체수정 | Ryn+Bolt | success | T1~T5 해결 (8파일 +204/-85) |
| 2026-04-06 | 크로스 리뷰 | Zen | pass | HIGH 2건 즉시 수정 |
| 2026-04-07 | 자동 비용 추적 | Ryn | success | log-add-usage + budget_estimate_cost |
| 2026-04-07 | MD 파일 정비 | Ryn | success | README/QUICKSTART/PHILOSOPHY 동기화 |
| 2026-04-18 | 자동승급 시스템 점검 | Ryn | success | |
| 2026-04-18 | 랭크 승급: novice→junior | Ryn | success | 누적 11건 (≥10 충족) |
| 2026-04-19 | web-ui 기반 작업 시작 | Ryn+Kai | success | feature/web-ui 브랜치 (Tier A) |
| 2026-04-25 | Tier B — pytest 90개 + claude session GC | Zen+Ryn | success | 49c4cd1, 0.84초 통과 |
| 2026-04-25 | Tier C1 — 글로벌 skills 통합 | Ryn+Kai | success | 11e3681, 35개 OMC 스킬 노출 |
| 2026-04-25 | Tier C2 — SOUL handoff 시각화 | Kai | success | SoulHandoffCard.vue 180줄 |
| 2026-04-25 | tool.completed result 기록 | Kai | success | 3cd4e97, 펼치기 활성화 |
| 2026-04-25 | 동시 tool 정확 매칭 | Kai | success | 8d8b531, tool_use_id strict |
| 2026-04-25 | toolResult 256KB cap | Kai | success | ed8f2e8, 트런케이션 마커 |
| 2026-04-25 | forge-init 재분석 (v3) | Nex+architect | success | analysis.md/forge-board.md 갱신 |
| 2026-04-25 | install.sh fix 검증 (재설치 후 forge-board 경고 사라지는지) | bolt | success |  |

## 다음 작업 후보 (분석 결과 기반)

1. **chat run terminal 후크 도입** (HIGH) — `api_runs.py:on_terminal`에서 `forge log-add` 호출 → 자동 승급/업적 통합
2. **schema_version 마이그레이션** (HIGH) — `sessions_db.py`에 ALTER 분기 + 백업 hook
3. **Bash 단위 테스트** (MEDIUM) — bats-core 도입, 최소 soul-parser/growth-log/rank-system
4. **Pydantic SoulDetail 확장** (MEDIUM) — tools/maxTurns/disallowed_tools 노출 → Vue가 director 격리 시각화 가능
5. **Vue chat.ts 메시지 cap** (LOW) — 500개 초과 시 head trim
