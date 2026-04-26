---
analyzed: 2026-04-25
analyzer: OMC explore + architect (opus)
previous: 2026-04-18
scope: feature/web-ui 브랜치 (Tier A→B→C) 반영
---

# GolemGarden 프로젝트 분석 결과 (v3)

## 개요

- **프로젝트 유형**: 3-tier 하이브리드 시스템 — Bash CLI 코어 + Python FastAPI 게이트웨이 + Vue 3 웹 UI
- **언어 비중**: Bash ~8.8K LOC, Python ~4.7K LOC, TypeScript/Vue ~3K+ LOC, Markdown/YAML ~2.5K+ LOC
- **플랫폼**: Claude Code CLI + OMC 위에서 동작 (CLI 우선 철학 유지)
- **포터빌리티**: agentskills.io 호환 (SOUL Spec v1.0)
- **현재 브랜치**: `feature/web-ui` (Tier C 진행 중)

## 규모 (2026-04-18 대비 변화)

| 항목 | 4/18 | 4/25 | 변화 |
|------|------|------|------|
| lib/ 모듈 | 28개 | 30개 | +2 |
| lib/ 코드 | 7,707줄 | 7,784줄 | +1% |
| forge.sh | 1,060줄 | 1,052줄 | -1% (정리) |
| **web/gateway** (신규 영역) | - | 19 모듈 / 4,753줄 | NEW |
| **web/client** (신규 영역) | - | 44 컴포넌트 / 12 페이지 | NEW |
| **pytest** (신규) | 0 | 90개 (0.84초) | NEW |
| skills/ | 6 | 6 | 동일 |
| spec/ | 3 | 3 | 동일 |
| SOUL 수 | 12 | 12 | 동일 |
| **총 LOC 추정** | ~10K | ~20K | **2배** |

## 아키텍처 (3-Tier)

### 데이터 흐름 (chat 1 turn)

```
Vue Client (chat.ts: RunEvent 6종 switch)
    ↓ HTTP POST /v1/projects/{id}/runs
Python Gateway (api_runs.py)
    ├── sessions_db.upsert_session + add_message (SQLite WAL)
    └── SessionManager.spawn_run
          → claude --session-id|--resume (mutually exclusive, prior_count 기반)
          → stream-json → events.parse_stream_event → asyncio.Queue
    ↓ SSE stream
Vue Client
    ├── tool.completed → tool_use_id 정밀 매칭 → updateMessage
    └── SoulHandoffCard (Task block 분기, workerLabel regex)
```

### 데이터 흐름 (forge 1회)

```
Vue Client → POST /v1/projects/{id}/forge
  ↓
ForgeRunner (whitelist + 9종 금지문자 + env allowlist)
  ↓
bash forge.sh <cmd> <args>  (subprocess, minimal env)
  ↓
lib/30 모듈 lazy-load + JSONL/SQLite 직접 쓰기
```

### 모듈 의존성 (Bash 코어)

```
soul-parser.sh [FOUNDATION — 20+/30 모듈 의존, 즉시 source]
  └── growth-log.sh
        ├── rank-system.sh → 자동 승급 (tools/maxTurns/isolation 갱신)
        ├── prompt-builder.sh → error-recovery.sh (13종 에러 분류)
        ├── insights.sh, lesson-extractor.sh, dashboard-unified.sh
        ├── soul-to-skill.sh, skill-to-soul.sh (포터빌리티)
        └── mailbox.sh, session.sh, worktree.sh, achievement.sh, chemistry.sh ...
```

### 자동화 체인 (변동 없음, 안정 운영 중)

```
forge log-add → growth_log_append
            → rank_promote (자동, soul-parser._sed_i로 frontmatter 갱신)
            → achievement_check (자동, 뱃지 수여)
```

## 신규 기능 (4/18 이후 추가) — feature/web-ui 브랜치

### Tier A — Setup + 기본 기능
- web/gateway FastAPI 게이트웨이 신설 (uvicorn ≥0.46, Python ≥3.13, uv 빌드)
- web/client Vue 3.5 + Pinia 3 + Vite 8 + Naive UI + vue-i18n (en/ko)
- Hermes 코드를 native로 흡수

### Tier B — 품질 보증 (49c4cd1)
- **pytest 90개** 도입 (0.84초): registry 14, sessions_db 21, forge_runner 16, session_manager 15, api_runs 5, claude_sessions 4, global_skills 10
- claude session GC: `claude_sessions.py` (UUID regex 기반 안전 삭제, 3가지 명명 fallback)
- 보안 invariants: forge whitelist (27 cmd), 9종 금지문자, env allowlist (`_FORGE_ENV_KEEP`), $HOME 경로 강제
- session UX: SessionListItem message_count 뱃지, ProfileCard "세션 정리" 버튼

### Tier C — 협업 시각화
- **C1 — 글로벌 skills 통합** (11e3681): `~/.claude/skills/` 35개 OMC 스킬을 `GET /v1/skills/global`로 노출, mtime 캐시
- **C2 — SOUL handoff 시각화** (11e3681): `SoulHandoffCard.vue` (180줄) — Director→Worker 분배 카드, workerLabel regex 추출, 랭크별 보더
- **C2 fix — tool result 기록** (3cd4e97): `chat.ts`가 `tool.completed.result`를 메시지에 기록 → SoulHandoffCard 펼치기 활성화
- **C2 fix — 동시 tool 매칭** (8d8b531): `tool_use_id` 정밀 매칭, subagent_type prefix 정리
- **C2 fix — toolResult 캡** (ed8f2e8): 256KB cap + 트런케이션 마커

## 아키텍처 소견 (architect 분석)

### 강점

1. **forge_runner 다층 방어선**: 명령 화이트리스트(27종) + per-arg 512자/총 30개 제한 + 9종 금지문자 + env allowlist (ANTHROPIC_API_KEY/AWS/npm credential 차단)
2. **subprocess env 비대칭이 정당함**: claude는 full-env 상속(API key 필요), forge는 minimal env. 코드 주석으로 명시.
3. **SQLite WAL + open-per-call**: FastAPI 스레드풀 cross-thread 공유 회피, Windows 파일 핸들 명시 처리
4. **SSE 큐 단일 소비자 + 터미널 이벤트 보장**: `_TERMINAL_EVENTS`는 절대 드랍 X (queue full 시 stale evict), 두 번째 client는 409 거부
5. **Vue chat.ts의 tmux-like resume**: SSE drop 시 polling 전환, `pollSignatures` 안정성 검증, `serverIsAhead` 비교로 localStorage vs 서버 충돌 해결
6. **Phase 8 session-id 결정 트리**: `prior_turn_count` 명시 파라미터로 race 회피, `--session-id` vs `--resume` mutually exclusive invariant

### 약점 / 새로 식별된 부채

| # | 부채 | 우선순위 | 위치 |
|---|------|---------|------|
| **1** | **데이터 정합성 비대칭** — Gateway는 sessions.db에만 쓰고, Bash는 growth-log/jsonl에만 쓴다. 두 writer가 같은 도메인 이벤트(SOUL 작업 완료)를 각자 기록하며 동기화 X | **HIGH** | api_runs.py:191-216 / growth-log.sh:51 |
| **2** | **schema_version 마이그레이션 미구현** — `CURRENT_SCHEMA_VERSION=1` 고정, ALTER 로직 부재. 다음 schema 변경 시 silent corruption 가능 | **HIGH** | sessions_db.py:121-126 |
| 3 | SOUL 정의 3중 노출의 비대칭 — Bash는 tools/maxTurns/disallowed_tools/is_coordinator를 강제하지만 Pydantic SoulDetail은 미노출 → Vue는 director 격리를 모름 | MEDIUM | souls.py:15-28 |
| 4 | **테스트 비대칭** — Python 90개 vs Bash **0개** vs Vue 미확인. forge.sh 1052줄 + lib/ 8836줄이 단위 테스트 없이 운영 | MEDIUM | tests/bats/ 신규 필요 |
| 5 | `_VALID_SKILL_ID` symlink 회피의 명시적 가정 — single-user localhost 가정. multi-user 전환 시 정면충돌 | LOW | skills.py:144-149 |
| 6 | forge.sh 내부 escape — 외부 args는 견고하나 forge.sh는 `eval`/변수확장 사용. 새 subcommand 추가 시 회귀 위험 | LOW | forge.sh:48 |

### 4/18 부채 추적

| # | 부채 | 4/18 | 4/25 |
|---|------|------|------|
| 1 | JSONL 인젝션 | 부분 해결 | **부분 해결** (변동 없음) |
| 2 | 승급 로직 중복 | 해결 | 해결 |
| 3 | 무조건 모듈 로딩 | 해결 | 해결 |
| 4 | 글로벌 변수 오염 (soul_parse) | 미해결 | **해결** (4/26 mutation 검증 — 13개 SOUL_* 모두 매 호출 명시 재할당, EFFORT/DISALLOWED_TOOLS/IS_COORDINATOR 3개 invariant 테스트화) |
| 5 | 경로 순회 검증 | 해결 | **재검토 필요** (registry $HOME 검증은 해결, basename 가드는 모듈별 상이) |

### 핵심 도메인 분포

비즈니스 로직(SOUL persona + 성장/랭크/케미)의 **무게 중심은 Bash에 있다**. Gateway는 거의 read-only 어댑터:

| 비즈니스 규칙 | Bash | Python/Vue |
|---|---|---|
| Director 도구 격리 | ✅ soul-parser.sh:126-133 | ❌ 미노출 |
| Rank 기반 도구/maxTurns 기본값 | ✅ soul-parser.sh:113-140 | ❌ 미노출 |
| 자동 승급 트리거 | ✅ rank-system.sh + forge.sh:317 | ❌ 호출만 |
| 성장 기록 append | ✅ growth-log.sh:51 (writer) | 📖 activity.py (reader only) |
| 세션 메시지 영속화 | ❌ | ✅ sessions_db.py (writer) |
| SOUL 매칭 점수 | ✅ soul-parser.sh:243-258 | ❌ |
| 메일박스 writer | ✅ mailbox.sh | 📖 read only |

### 확장 위험 지점 (Blast Radius)

1. **soul-parser.sh의 `soul_parse()`** — 15개 전역 변수 덮어쓰기, 단일 레벨 save/restore 스택. 20+/30 모듈 의존
2. **growth-log.sh의 자동 승급 + 업적 체인** — `rank_promote 2>/dev/null` silent 실패가 디버그 어렵게 함
3. **sessions_db.py 스키마 변경** — auto-migration 부재, WAL은 ALTER에 도움 안 됨
4. **chat.ts의 RunEvent 타입** — 6종 switch에 default 없어 silent drop, `tool_use_id` 의존성
5. **CLAUDE_CMD resolution** — Windows .cmd → .exe wrapper 형식 변경 시 graceful degradation 없음

### 보안 고려사항

- forge_runner 외부 경계는 견고. **forge.sh 내부에서 eval/변수확장은 invariant로 유지** (string-only args)
- `GOLEM_EXTRA_PROJECT_ROOTS`는 Gateway + forge.sh 양쪽에 전파 (forge_runner _FORGE_ENV_KEEP 포함). 노출 범위 문서화 필요
- 글로벌 스킬 스캔 path-resolution은 symlink 회피 가정에 의존 — single-user localhost 한정
- sessions.db FK는 manual cascade (ON DELETE CASCADE 미적용, v0.5 마이그레이션 대기)

### 성능 병목 가능 지점

- Bash subprocess startup이 hot path (forge 호출당 새 bash 프로세스, lazy load의 한계)
- mtime 캐시 일관성: souls.py / skills.py / activity.py `_growth_cache` 각각 별도 invariant
- SQLite open-per-call cost (chat 1 turn에 5-10회 누적, Windows 파일 핸들 alloc)
- chat.ts messages 배열 길이 cap 없음 (256KB는 단일 항목 cap이지 배열 길이 cap 아님)

## Tier B/C 도입 후 변화한 시스템 특성

### 새로 생긴 invariant (Tier B)

- forge command must be in whitelist (27종)
- args에 shell metachar 금지 (9종: `;|&<>` `` ` `` `$\n\r`)
- forge subprocess는 minimal env (ANTHROPIC_API_KEY 차단)
- project path는 `$HOME` 아래 (또는 `GOLEM_EXTRA_PROJECT_ROOTS`)
- sessions.db: per-connection FK + WAL
- session_id는 UUID v4 (서버측 자동 재생성)
- `--session-id`와 `--resume`은 mutually exclusive (`prior_turn_count` 기반 분기)
- run당 SSE consumer 1개 (409 on duplicate)
- 터미널 이벤트는 절대 드랍하지 않음

### 새로 생긴 invariant (Tier C)

- `tool_use_id` 정밀 매칭 (chat.ts:878-891) — fallback 전 strict match
- `~/.claude/skills/` 글로벌 스킬은 mtime 캐시
- toolResult 256KB cap (chat.ts:910 `TOOL_RESULT_CAP`)

### 깨진/약화된 invariant

- **"forge.sh가 SoT"** → 4/18까지는 forge.sh가 모든 SOUL 작업을 기록. 4/25 현재 chat은 sessions.db로만 흐르고 forge.sh의 growth-log에 기록되지 않는다. **두 갈래의 SoT가 공존**
- **"Bash가 frontmatter 단일 작성자"** → `_sed_i`가 여러 모듈에서 호출 (rank-system 자동 승급 등). 동시 forge 실행 race 가능 (현재 lock 부재)

## Root Cause (architect 결론)

> 현재 시스템의 가장 깊은 부채는 **"도메인 데이터 writer가 두 군데로 갈라졌다"**는 것이다. 4/18까지는 forge.sh가 모든 SOUL 작업을 기록했다. Tier B/C가 chat 채널을 추가하면서 sessions.db라는 두 번째 writer가 생겼는데, 둘이 **같은 도메인 이벤트를 각자 기록하면서 서로의 존재를 모른다**.

이 부채는 두 가지 후속 문제를 낳는다:

1. **chat에서는 자동 승급이 트리거되지 않는다** — 100턴 대화해도 rank up 발생 X. `forge log-add`를 별도로 호출해야만
2. **sessions.db schema_version 마이그레이션 가드 부재** — 다음 schema 변경 시 기존 사용자 DB broken

## 권고 (우선순위순)

| # | 권고 | 비용 | 효과 |
|---|------|------|------|
| **1** | **chat run terminal 시 forge log-add 호출 후크** — 데이터 통합, 자동 승급/업적 활성화 | 중 (1일) | 매우 높음 |
| **2** | **sessions.db schema_version 마이그레이션 프레임워크** — ALTER 분기 + 백업 hook | 중 (반나절) | 높음 |
| **3** | **Bash 단위 테스트 도입 (bats-core)** — 최소 soul-parser, growth-log, rank-system | 고 (2-3일) | 높음 |
| 4 | soul_parse 글로벌 변수 오염 해결 (assoc array 또는 stdout JSON) | 중 | 중 |
| 5 | Pydantic SoulDetail에 tools/maxTurns/disallowed_tools 노출 | 저 | 중 |
| 6 | Hermes Agent 플러그인 시작 — Python 코어 단계적 이전 (Phase 3) | 고 (수주) | 매우 높음 |
| 7 | forge_runner 새 subcommand 추가 시 args contract docstring + test | 저 | 중 |
| 8 | Vue chat.ts messages 배열 길이 cap (예: 500개 초과 시 head trim) | 저 | 저 |
| 9 | claude_sessions.py layout fallback 후 대시보드 경고 | 저 | 중 |
| 10 | settings.json에 sessions.db / projects.json 백업 자동화 hook | 저 | 중 |

## 현재 팀 구성 평가

### 활동 SOUL (5/12 — 4/18 대비 +2)

| SOUL | Role | Rank | 변화 | 비고 |
|------|------|------|------|------|
| **Ryn** | backend-developer | **junior** | streak_5, tasks_10, streak_10 신규 | Bash + Python (게이트웨이) 주력 |
| **Kai** | frontend-developer | novice | **신규 활동** (first_blood, streak_5) | Vue 3 + Pinia + Naive UI 작업 |
| **Bolt** | devops-engineer | novice | **신규 활동** (first_blood) | uv/Vite/install 관리 |
| **Zen** | qa-tester | novice | 동일 | pytest 90개 도입 주도 |
| **Nex** | director | junior | 동일 | 팀 빌드 시 분배 |

### 비활동 SOUL (7/12)

| SOUL | Role | 평가 |
|------|------|------|
| **Sage** | knowledge-auditor | **유지** — 지식 승격 심사 시 호출 |
| Glitch | game-logic-developer | 대기 (게임 프로젝트용) |
| Oracle | data-analyst | 대기 (트레이딩용) |
| Pixel | frontend-developer | 대기 (Kai와 중복) |
| Scout | data-analyst | 대기 (뉴스 분석용) |
| Sentinel | security-auditor | 대기 (트레이딩용) |
| Sprite | game-designer | 대기 (게임용) |

### 팀 구성 권고

이 프로젝트(GolemGarden 자체 개발)에 **실제 필요한 SOUL은 6명**:
- **Nex** (Director), **Ryn** (Backend Bash + Python), **Kai** (Frontend Vue/TS), **Zen** (QA pytest/vitest), **Bolt** (DevOps install/uv/Vite), **Sage** (Auditor)

**Kai 정합성**: 4/18 보드에는 미등록이었으나 4/25 시점 growth-log/kai.jsonl + achievements 활동 확인. 보드에 정식 등록 필요.

## 남은 과제 (재정렬, 우선순위순)

1. **데이터 통합** (NEW, HIGH) — chat run terminal에 forge log-add 후크
2. **schema_version 마이그레이션** (NEW, HIGH) — sessions.db 변경 안전성
3. **Bash 단위 테스트** (NEW, MEDIUM) — bats-core 도입
4. **글로벌 변수 오염** (4/18부터 미해결) — soul_parse 리팩터
5. **JSONL 인젝션 완전 해결** (4/18부터 부분 해결) — 모든 입력 경로 escape
6. **Pydantic SOUL 모델 확장** (NEW, MEDIUM) — tools/maxTurns/disallowed_tools 노출
7. **Python 코어 추출 시작** (전략, Phase 3) — SOUL Spec 기반 플랫폼 독립
8. **Hermes Agent 플러그인** (전략, Phase 3 후속)
