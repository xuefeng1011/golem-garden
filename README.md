# GolemGarden — 독립형 AI 에이전트 육성 엔진

> *AI는 널렸다. 우리는 장인을 만든다.*

## 컨셉

GolemGarden은 Claude Code CLI 위에서 직접 동작하는 독립 에이전트 엔진이다.
골렘을 심고, 키우고, 팀으로 엮는 정원.
oh-my-claudecode(OMC)는 선택적 확장이다 — 엔진 실행에 필수가 아니다.

GolemGarden이 제공하는 것:
- **SOUL 시스템**: 에이전트 페르소나 + 성장 기록
- **포지 보드**: 프로젝트 단위 에이전트 팀 구성 + 역할 분배
- **커스텀 SOUL 생성기**: 대화형으로 새 에이전트 페르소나 생성
- **도메인 스킬 팩**: 특화 분야별 스킬 번들 (게임 개발, 주식 분석 등)

---

## 아키텍처

```
┌─────────────────────────────────────────────────┐
│              GolemGarden Layer                    │
│                                                 │
│  ~/.claude/golem-garden/                         │
│  ├── souls/            ← SOUL 페르소나            │
│  │   (tools, maxTurns, isolation, effort 포함)   │
│  ├── lib/ (30개 모듈)                             │
│  │   ├── soul-parser, growth-log, rank-system   │
│  │   ├── prompt-builder (캐시 최적화)             │
│  │   ├── mailbox (SOUL간 통신)                    │
│  │   ├── session (세션 지속성)                     │
│  │   ├── error-recovery (3단계 복구)              │
│  │   └── worktree (Git 격리 실행)                 │
│  ├── growth-log/       ← 성장 + 비용 추적         │
│  └── domain-packs/     ← 팀 번들                  │
│                                                 │
│  .golem/ (프로젝트별)                              │
│  ├── souls/            ← 프로젝트 오버라이드       │
│  ├── mailbox/          ← SOUL 간 메시지           │
│  ├── sessions/         ← 작업 트랜스크립트         │
│  ├── worktrees/        ← Git worktree 격리        │
│  ├── memory/           ← SOUL별 학습 기억          │
│  ├── retrospectives/   ← 자동 회고 보고서          │
│  ├── chemistry.jsonl   ← 팀 케미 데이터            │
│  ├── achievements.jsonl← 업적/뱃지                 │
│  ├── skill-trees.jsonl ← 전문화 분기               │
│  ├── project-dna.json  ← 프로젝트 지문             │
│  └── forge-board.md    ← 팀 구성                  │
│                                                 │
│  ~/.claude/skills/golem-garden/                   │
│  ├── SKILL.md (메타 라우터)                        │
│  ├── forge-init/ forge-team/ forge-review/       │
│  └── forge-sync/                                │
├─────────────────────────────────────────────────┤
│         oh-my-claudecode (OMC) — 선택 사항       │
│  32 agents | 31+ skills | 5 exec modes          │
│  Model routing | HUD | Token optimization       │
├─────────────────────────────────────────────────┤
│            Claude Code CLI (필수)                │
│         Claude Max $100/월 구독                  │
└─────────────────────────────────────────────────┘
```

---

## SOUL 시스템

### SOUL.md 구조

각 에이전트는 `souls/` 디렉토리에 페르소나 파일을 갖는다.
OMC의 에이전트 커스터마이징 시스템과 호환되는 포맷.

```markdown
---
name: Ryn
role: backend-developer
rank: novice          # novice → junior → senior → lead → master
specialty: [spring-boot, mariadb, rest-api, jpa, clean-architecture]
personality: 꼼꼼하고 보수적. (사용자 메모용, 프롬프트 미주입)
model: sonnet         # 기본 모델 (OMC 라우팅과 연동)
tools: [Read, Edit, Grep, Glob]
maxTurns: 15
isolation: none
effort: medium
created: 2026-03-30
---

## 프로젝트 컨텍스트 (프롬프트에 주입됨)
- 기술스택: Spring Boot 3.x + WebFlux, MariaDB
- 아키텍처: Clean Architecture + CQRS 패턴
- 코드 컨벤션: OpenAPI 스펙 선행, 마이그레이션 스크립트 동반
- 우선순위: 에러 핸들링 > 테스트 커버리지 > 기능 완성

## 전문 지식 (컨텍스트 힌트로 주입)
- MariaDB 성능 튜닝, 인덱스 전략
- JPA N+1 문제 해결 패턴
- P6Spy 드라이버 호환성 주의사항

## 성장 기록 요약 (이력으로 주입)
- 2026-03-30: 생성 (Novice)
- (자동 누적 → "이전 작업 이력 N건, 성공률 X%"로 요약 주입)
```

### 랭크 시스템

| 랭크 | 조건 | 권한 | 허용 도구 |
|------|------|------|----------|
| Novice | 생성 직후 | 단일 파일 수정, 리뷰 필수 | Read, Edit, Grep, Glob |
| Junior | 태스크 10회 | 멀티파일 수정, 테스트 작성 | + Write, Bash |
| Senior | 50회 + 무결함 10연속 | 아키텍처 제안, worktree 격리 | + Agent, WebFetch |
| Lead | 100회 | 팀 오케스트레이션 | + SendMessage |
| Master | 200회 | 모든 권한, 리뷰 면제 | + TaskCreate (전체) |

성장 기록은 `growth-log/{name}.jsonl`에 자동 누적:
```json
{"date":"2026-04-02","task":"REST API 설계","result":"success","files_changed":5,"tests_passed":12,"tokens_in":15000,"tokens_out":8000,"tokens_cache":12000,"cost_usd":0.087,"model":"sonnet","duration_ms":45000}
```

---

## GolemGarden 스킬

### 1. forge-init (프로젝트 초기화)

```markdown
---
name: forge-init
description: GolemGarden 프로젝트 초기화. 팀 구성과 SOUL 파일 생성.
---

## 워크플로우
1. 프로젝트 유형 파악 (웹앱, API, 풀스택 등)
2. 필요한 역할 선정 (backend, frontend, qa, devops 등)
3. souls/ 디렉토리에 SOUL.md 파일 생성
4. forge-board.md에 팀 구성 기록
5. OMC 에이전트 매핑 설정
```

### 2. forge-team (팀 실행)

```markdown
---
name: forge-team
description: GolemGarden 팀 단위 작업 실행. SOUL 기반 역할 분배.
---

## 워크플로우
1. forge-board.md에서 현재 팀 구성 로드
2. 태스크를 SOUL 역할에 따라 분배
3. OMC의 실행 모드 선택:
   - 단순 태스크 → autopilot
   - 대규모 → ultrapilot (SOUL별 병렬)
   - 비용 절약 → ecomode
4. 각 SOUL의 행동 원칙을 프롬프트에 주입
5. 완료 후 growth-log에 기록
```

### 3. forge-review (팀 리뷰)

```markdown
---
name: forge-review
description: GolemGarden 팀 크로스 리뷰. 다른 SOUL이 코드 리뷰.
---

## 워크플로우
1. 작업자 SOUL과 다른 역할의 SOUL을 리뷰어로 지정
2. 리뷰어 SOUL의 전문 지식 + 행동 원칙 기반 리뷰
3. 피드백 반영 후 growth-log에 리뷰 결과 기록
4. 무결함 연속 카운트 업데이트 → 랭크 승급 체크
```

### 4. forge-sync (지식 승격)

```
Sage(심사관)가 프로젝트 학습을 검증 후 글로벌 SOUL에 반영.
5단계 오염 방지 체크리스트 적용.
```

### 5. 통신/세션/복구 시스템

```
- forge mailbox: SOUL간 JSONL 기반 메시지 교환
- forge session: 작업 트랜스크립트 + 재개
- forge recover: 3단계 실패 복구 (재시도→위임→에스컬레이션)
- forge worktree: Git worktree 기반 SOUL 격리 실행
- forge dashboard --cost: SOUL별 비용 대시보드
- forge log-add-usage: Agent usage 기반 자동 비용 추적
```

### 6. 성장 엔진 (GolemGarden만의 차별점)

| 시스템 | 설명 | 명령 |
|--------|------|------|
| **SOUL Memory** | 과거 태스크 교훈을 기억, 유사 작업 시 프롬프트 자동 주입 | `forge memory` |
| **Retrospective** | 빌드 후 자동 회고 (잘된 점/개선점/비용) | `forge retro` |
| **Chemistry** | SOUL 쌍별 협업 점수 S~F 등급, 최적 팀 구성 | `forge chemistry` |
| **Achievement** | 15개 뱃지 (First Blood ~ Grandmaster) | `forge achievement` |
| **Skill Tree** | Senior 승급 시 전문화 브랜치 선택 | `forge skill-tree` |
| **Project DNA** | 프로젝트 지문 + SOUL 이동 적응도 측정 | `forge dna` |
| **Budget Tracker** | 토큰/USD 예산 + 수확체감 감지 | `forge budget` |
| **Tool Character** | 도구 성격 메타데이터, 병렬 안전성 판단 | `forge tool-char` |

---

## OMC 연동 매핑

GolemGarden SOUL → OMC 에이전트 매핑:

| GolemGarden SOUL | OMC Agent | 모델 | 도구 제한 |
|-----------------|-----------|------|----------|
| Nex (Director) | architect | opus | Agent, SendMessage, TaskCreate, TaskStop |
| Ryn (Backend) | executor | sonnet | rank 기반 점진적 확장 |
| Kai (Frontend) | designer | sonnet | rank 기반 점진적 확장 |
| Zen (QA) | test-engineer | haiku | Read, Edit, Grep, Glob |
| Sage (Auditor) | code-reviewer | opus | Read, Edit, Write, Bash, Grep, Glob |
| Bolt (DevOps) | executor | sonnet | rank 기반 점진적 확장 |

OMC 실행 모드 매핑:

| GolemGarden 명령 | OMC 실행 |
|----------------|----------|
| `forge build` | ultrapilot (SOUL별 병렬) |
| `forge quick` | autopilot |
| `forge save` | ecomode |
| `forge review` | pipeline (작업 → 리뷰 순차) |

---

## 설치 및 사용

### Prerequisites

| 도구 | 최소 버전 | 용도 |
|------|----------|------|
| Bash | 4.0+ (Git Bash on Windows) | forge.sh / lib 실행 |
| Python | 3.13+ | web/gateway (FastAPI) |
| Node | 23+ | web/client (Vite/Vue) |
| uv | 최신 | Python 의존성 관리 |
| Claude CLI | 최신 | agent 실행 |

### 설치

```bash
# 1. GolemGarden Bash 코어 설치
git clone https://github.com/xuefeng1011/golem-garden.git
cd golem-garden
bash install.sh

# 3. (선택) Web UI dev 환경 셋업 — cross-platform
cd web/gateway && uv sync           # Python deps
cd ../client && npm install         # Node deps
npm run dev                         # Vite dev server (5173)
# 별도 터미널에서:
cd web/gateway && uv run uvicorn golem_gateway.main:app --reload
```

> Windows 의 경우 `web/setup.ps1` 한 번 실행으로 위 3-step 자동화 (한글 username junction 포함). 자세한 내용은 하단 "Web UI" 섹션 참조.

### Testing

```bash
# Bash 단위 테스트 (bats-core 1.11.0 vendored)
bash tests/bats/run.sh

# Gateway 단위 테스트 (pytest 187 케이스)
cd web/gateway && uv run pytest

# Client 단위 테스트 (vitest + happy-dom)
cd web/client && npm test
```

### 사용

```bash
# 프로젝트 초기화 — 팀 구성
forge-init: 풀스택 웹앱, Spring Boot + React

# 팀 빌드 — SOUL별 병렬 실행
forge build: 사용자 인증 API + 로그인 화면

# 비용 절약 모드
forge save: README 업데이트

# 크로스 리뷰
forge review: Ryn이 작성한 AuthController를 Zen이 리뷰
```

---

## 로드맵

### Phase 1: 기반 구축 — 완료
- [x] SOUL.md 템플릿 + 12개 글로벌 SOUL
- [x] forge-init / forge-team / forge-review 스킬
- [x] SOUL → OMC 에이전트 매핑 + 프롬프트 주입
- [x] Growth-log 자동 기록 + 랭크 시스템
- [x] SOUL 스키마 공식화 (tools, maxTurns, isolation, effort)
- [x] 비용 추적 (tokens, cost_usd per task)
- [x] 프롬프트 캐시 최적화 (공통/SOUL별 분리)

### Phase 2: 통신 체계 — 완료
- [x] 메일박스 시스템 (SOUL 간 파일 기반 통신)
- [x] 세션 지속성 (트랜스크립트 + resume/status)
- [x] 에러 복구 (3단계: 재시도→위임→에스컬레이션)
- [x] Coordinator 프로토콜 (Nex 4단계 워크플로)
- [x] Hook 확장 (guard-novice, auto-growth-log, guard-mailbox)

### Phase 3: 격리와 병렬성 — 완료
- [x] Worktree 격리 (SOUL별 git worktree)
- [x] 도구 실제 제한 (rank 기반 tools 필드)
- [x] forge-team 스킬 강화 (세션/메일박스/복구 연동)

#### GolemGarden 고유 기능 — 완료
- [x] SOUL Memory (학습 기억 + 프롬프트 자동 주입)
- [x] Retrospective (자동 회고)
- [x] Chemistry (팀 케미 S~F)
- [x] Achievement (15개 뱃지)
- [x] Skill Tree (전문화 분기)
- [x] Project DNA (프로젝트 지문)
- [x] Budget Tracker (수확체감 감지)
- [x] Tool Character (도구 성격 메타데이터)
- [x] Withholding Pattern (에러 보류 복구)
- [x] Fork Cache Optimization (byte-identical prefix)

### Phase 3.5: 품질 강화 — 완료
- [x] `_json_escape()` — 모든 JSON 문자열 안전 이스케이프 (newline/tab/quote/backslash)
- [x] 경로 순회 방지 — `_resolve_soul_file()`, `forge_worktree_create()` 입력 검증
- [x] 승급 로직 통합 — `rank_should_promote()` 단일 함수 (rank-system + global-sync)
- [x] Lazy loading — forge.sh 24개 모듈 중 21개 온디맨드 로딩
- [x] JSONL 요약 캐시 — `.summary` 사이드카로 O(1) 조회
- [x] 자동 비용 추적 — `log-add-usage` (Agent usage → 모델별 가격 자동 계산)

### Phase 4: Web UI + 품질 보증 — 완료 (4/26 기준 PR #1~#4 머지)
- [x] **3-tier 아키텍처** — Bash CLI + Python FastAPI Gateway + Vue 3 Client
- [x] **N1: chat 종료 후크** (`growth_log.py`) — Gateway 가 Bash 와 동일 schema 로 자동 기록 → 자동 승급/업적 통합
- [x] **N2: SQLite schema_version 자동 마이그레이션** — PRAGMA user_version + WAL checkpoint
- [x] **N3: SoulDetail 6 필드 전체 노출** — backend (Pydantic) + frontend (Vue + i18n + 헬퍼 분리)
- [x] **N4: Bash 단위 테스트 도입** — bats-core 1.11.0 vendoring, soul-parser/growth-log/rank-system 커버
- [x] **부채 #4 종결** — `soul_parse()` 글로벌 변수 누설 mutation-validated strong invariant 3종
- [x] **vitest 도입** — happy-dom 기반, 13+ 케이스
- [x] **forge-board 마크다운 평탄화** — `_strip_inline_emphasis` parser hardening + snake_case 식별자 보존 회귀 가드 (PR #4)

### Phase 5: TypeScript 전환 — 미착수 (선택)
- [ ] 핵심 라이브러리 TS + Zod 전환
- [ ] MCP 서버화

---

## 역할 커스터마이즈 동작 원리

### 핵심 원칙: SOUL은 족쇄가 아니라 나침반

SOUL.md는 OMC 에이전트의 능력을 **제한하지 않는다**.
OMC coder는 이미 충분히 유능하다. SOUL은 그 능력의 **방향**만 잡아준다.

```
❌ 잘못된 방식 (능력 제한):
  "너는 Ryn이다. 반드시 이 원칙만 따라라.
   Spring Boot만 써라. 테스트 없으면 멈춰라."
  → OMC coder 본래 능력을 가두는 족쇄
  → 프롬프트 길어짐 → 성능 저하

✅ 올바른 방식 (컨텍스트 제공):
  "프로젝트 컨텍스트:
   - 기술스택: Spring Boot 3.x, MariaDB
   - 아키텍처: Clean Architecture + CQRS
   - 우선순위: 테스트 커버리지 > 빠른 구현
   - 코드 스타일: 한국어 주석, camelCase
   이 컨텍스트에서 최선의 방법으로 구현하라."
  → OMC coder 능력 100% 유지, 방향만 안내
```

즉 SOUL.md는 에이전트의 **성격표**가 아니라 **프로젝트 매뉴얼**에 가깝다.

### SOUL.md의 역할 범위

| SOUL이 하는 것 | SOUL이 하지 않는 것 |
|---------------|-------------------|
| 기술스택 컨텍스트 제공 | 특정 기술만 강제 |
| 코드 컨벤션 안내 | 구현 방식 제한 |
| 우선순위 힌트 | 판단 능력 대체 |
| 프로젝트 히스토리 전달 | 과거 실수 반복 강제 |
| 팀 내 역할 명시 | 다른 영역 접근 차단 |

SOUL의 `personality` 필드는 사용자가 읽기 위한 메모일 뿐,
프롬프트에 주입되는 것은 `specialty`, `행동 원칙`, `전문 지식`의
**컨텍스트 정보**다.

### SOUL → 프롬프트 주입 흐름

SOUL.md는 OMC 에이전트의 시스템 프롬프트에 **페르소나 레이어**로 주입된다.
OMC 에이전트 자체를 교체하는 게 아니라, 성격과 원칙을 덮어씌우는 구조.

```
사용자: "forge build: 인증 API 만들어줘"
         │
         ▼
① GolemGarden 스킬이 forge-board.md 읽음
   → 현재 팀: Nex(Director), Ryn(Backend), Zen(QA)
         │
         ▼
② Nex의 SOUL.md 로드 → 태스크 분석 + 역할 분배
   → "Backend API 필요 → Ryn 배정"
   → "테스트 필요 → Zen 배정"
         │
         ▼
③ Ryn의 SOUL.md 로드 → OMC coder 에이전트에 컨텍스트 주입
   프롬프트: "프로젝트 컨텍스트:
     기술스택: Spring Boot 3.x, MariaDB, Clean Architecture
     코드 컨벤션: OpenAPI 스펙 선행, 마이그레이션 스크립트 동반
     우선순위: 에러 핸들링 > 기능 완성 > 성능
     이전 작업 이력: REST API 설계 5건, 성공률 100%
     이 컨텍스트에서 다음 태스크를 수행하라: ..."
   (OMC coder의 능력은 그대로, 방향만 안내)
         │
         ▼
④ OMC가 실행 (ultrapilot 병렬)
         │
         ▼
⑤ 완료 후 growth-log에 기록 → 랭크 체크
```

### 역할 분배 모드 (3가지)

| 모드 | 명령 예시 | 동작 |
|------|----------|------|
| **자동 분배** | `forge build: 로그인 기능` | Nex(Director)가 분석 → SOUL별 자동 배정 |
| **수동 지정** | `forge assign ryn: AuthController` | 특정 SOUL만 지정 실행 |
| **리드 지정** | `forge build: 결제 시스템, ryn 리드` | Ryn 리드 + 나머지 자동 |

자동 분배 시 Nex(Director)의 판단 기준:
- SOUL의 `specialty` 태그와 태스크 키워드 매칭
- SOUL의 현재 `rank`에 따른 권한 범위 확인
- 가용 SOUL 중 최적 조합 선택

---

## 커스텀 SOUL 생성기

### forge-soul (대화형 SOUL 생성)

새 에이전트가 필요할 때 대화형으로 페르소나를 설계한다.

```bash
forge-soul: 새 에이전트 만들기

# 대화 흐름:
> 어떤 역할이 필요하세요?
  "DevOps 엔지니어"

> 이름을 지어주세요 (추천: Axel, Bolt, Cira, Dex)
  "Bolt"

> 성격은 어떤 스타일?
  1) 빠르고 과감한 실행가
  2) 신중하고 안전 우선
  3) 자동화 중독, 수작업 혐오
  4) 직접 입력
  "3"

> 전문 기술 스택은?
  "docker, k8s, github-actions, terraform"

> 행동 원칙을 정해주세요 (1~3개)
  "인프라 변경은 반드시 IaC로만"
  "모니터링 없는 배포는 배포가 아님"
```

결과: `souls/bolt.md` 자동 생성

```markdown
---
name: Bolt
role: devops-engineer
rank: novice
specialty: [docker, kubernetes, github-actions, terraform]
personality: 자동화 중독. 수작업은 죄악.
model: sonnet
created: 2026-03-30
---

## 행동 원칙
- 인프라 변경은 반드시 IaC로만
- 모니터링 없는 배포는 배포가 아님
- 반복 작업 발견 시 즉시 자동화 스크립트 제안

## 전문 지식
- Docker 멀티스테이지 빌드, compose orchestration
- Kubernetes 배포 전략 (Blue-Green, Canary)
- GitHub Actions CI/CD 파이프라인
- Terraform 모듈 설계

## 성장 기록 요약
- 2026-03-30: 생성 (Novice)
```

### SOUL 프리셋 라이브러리

자주 쓰는 역할은 프리셋으로 원클릭 생성:

| 프리셋 | 이름풀 | 기본 성격 |
|--------|--------|----------|
| Backend Developer | Ryn, Astra, Forge | 꼼꼼, 테스트 우선 |
| Frontend Developer | Kai, Lux, Pixel | 감각적, UX 집착 |
| DevOps Engineer | Bolt, Cira, Atlas | 자동화 중독 |
| QA/Tester | Zen, Sage, Iris | 의심 많음, 엣지케이스 사냥 |
| Data Analyst | Nova, Flux, Prism | 데이터로 말함, 시각화 우선 |
| Technical Writer | Echo, Quill, Reed | 명확한 문서, 독자 관점 |
| Security Auditor | Vex, Onyx, Shield | 편집증적 보안, 제로트러스트 |

---

## 도메인 스킬 팩

특화 분야별로 SOUL + 스킬을 번들로 제공.

### 🎮 게임 개발 팩

```
golem-garden/domain-packs/gamedev/
├── souls/
│   ├── sprite.md      (게임 디자이너 — 기획+밸런스)
│   ├── pixel.md       (그래픽/UI — Cocos, Canvas, 에셋)
│   └── glitch.md      (게임 로직 — 물리엔진, 충돌, AI)
├── skills/
│   ├── gamedev-init/SKILL.md     (프로젝트 보일러플레이트)
│   ├── gamedev-balance/SKILL.md  (밸런스 시뮬레이션)
│   └── gamedev-deploy/SKILL.md   (Toss 미니앱/웹 배포)
└── forge-board-gamedev.md        (팀 프리셋)
```

SOUL 예시 — Glitch (게임 로직):
```markdown
---
name: Glitch
role: game-logic-developer
specialty: [cocos-creator, canvas-api, physics, collision-detection]
personality: 퍼포먼스 광. 60fps 안 나오면 잠 못 잔다.
---
## 행동 원칙
- 게임 루프는 requestAnimationFrame 기반
- 오브젝트 풀링 필수, GC 최소화
- 모든 물리 계산은 deltaTime 기반
```

### 📈 주식/크립토 분석 팩

```
golem-garden/domain-packs/trading/
├── souls/
│   ├── oracle.md      (기술적 분석 — 차트, 지표)
│   ├── sentinel.md    (리스크 관리 — 포지션, 손절)
│   └── scout.md       (뉴스/센티먼트 — 소셜, 공시)
├── skills/
│   ├── trading-ta/SKILL.md       (기술적 분석 워크플로우)
│   ├── trading-backtest/SKILL.md (백테스트 자동화)
│   └── trading-alert/SKILL.md    (조건부 알림 설정)
└── forge-board-trading.md
```

### 🏗️ 풀스택 웹앱 팩

```
golem-garden/domain-packs/fullstack/
├── souls/
│   ├── nex.md         (아키텍트/디렉터)
│   ├── ryn.md         (백엔드)
│   ├── kai.md         (프론트엔드)
│   ├── zen.md         (QA)
│   └── bolt.md        (DevOps)
├── skills/
│   ├── fullstack-init/SKILL.md   (Spring+React 보일러플레이트)
│   ├── fullstack-api/SKILL.md    (REST/GraphQL 설계)
│   └── fullstack-deploy/SKILL.md (컨테이너 배포)
└── forge-board-fullstack.md
```

### 스킬 팩 설치

```bash
# 게임 개발 팩 활성화
forge pack install gamedev

# 주식 분석 팩 활성화
forge pack install trading

# 현재 팩 확인
forge pack list
```

---

## GolemGarden vs 직접 OMC 사용

| | 직접 OMC | GolemGarden on OMC |
|---|---|---|
| **에이전트** | 범용 32개, 이름 없음 | SOUL별 이름+성격+전문성 커스터마이즈 |
| **동작 원리** | OMC가 태스크 분석 → 에이전트 자동 선택 | SOUL.md를 OMC 에이전트에 프롬프트 주입 |
| **기억** | 세션 기반, 세션 끝나면 리셋 | SOUL별 growth-log 영구 누적 |
| **팀워크** | OMC 자동 배정만 | 자동/수동/리드지정 3가지 분배 모드 |
| **리뷰** | 단순 코드 체크 | SOUL 전문성 기반 크로스 리뷰 |
| **재사용** | 프로젝트마다 처음부터 | SOUL 포터블 (프로젝트 간 이동) |
| **확장** | 스킬 개별 추가 | 도메인 팩으로 SOUL+스킬 번들 설치 |
| **성장 기억** | 없음 | SOUL Memory — 과거 실수를 기억하고 반복 안 함 |
| **팀 케미** | 없음 | Chemistry — 데이터 기반 팀 최적화 |
| **업적** | 없음 | Achievement — 성장의 가시화 |

**핵심 차별점**: OMC는 "무엇을 할 것인가"에 집중.
GolemGarden는 "누가, 어떤 성격과 역량으로, 어떤 경험을 쌓아가며 할 것인가"를 추가.

---

## 비용

| 항목 | 비용 |
|------|------|
| Claude Max 구독 | $100/월 |
| OMC | 무료 (MIT) |
| GolemGarden | 무료 (자체 스킬) |
| 도메인 팩 | 무료 (자체 제작) |
| **합계** | **$100/월** |

---

---

## 🌐 Web UI

GolemGarden을 브라우저에서 운영. SOUL 팀 + 채팅 + 프로젝트 관리 + Forge 명령 실행.

### Quick Start (Windows)

```powershell
# 1. 자동 setup (junction + env + deps)
powershell -ExecutionPolicy Bypass -File web/setup.ps1

# 2. 새 셸 열기 (환경변수 적용)

# 3. 서버 기동
web\start-all.bat

# 4. 브라우저: http://localhost:5173
```

### 수동 setup

환경변수 4개를 직접 설정한다:

| 변수 | 값 | 목적 |
|------|-----|------|
| `GOLEM_FORGE_SH_BASH` | `/mnt/c/g-garden/forge.sh` | bash가 호출할 forge.sh 경로 |
| `MSYS_NO_PATHCONV` | `1` | Git for Windows path 자동변환 차단 |
| `MSYS2_ARG_CONV_EXCL` | `*` | argv path 변환 차단 |
| `GOLEM_EXTRA_PROJECT_ROOTS` | `C:/path1;C:/path2` | home 외 추가 등록 가능 root |

junction 생성 (한글 username인 경우):

```cmd
mklink /J C:\g-garden "%USERPROFILE%\.claude\golem-garden"
```

서버 기동:

```cmd
REM Gateway (port 8642)
cd web\gateway && python -m uv run python -m uvicorn golem_gateway.main:app --host 127.0.0.1 --port 8642 --app-dir src

REM UI dev server (port 5173)
cd web\client && npm run dev
```

### 아키텍처

```
브라우저 (Vue3 + naive-ui, port 5173)
        │ REST + SSE
        ▼
FastAPI Gateway (Python, port 8642)
        │ subprocess
        ▼
claude CLI (--session-id / --resume)
```

### 주요 기능

- 멀티 프로젝트 관리 (각자 독립 SOUL/skills)
- Director(Nex) 전담 채팅 + 다른 SOUL은 read-only 브라우저
- forge.sh 명령 UI 실행 (30 명령 카탈로그 + 라이브 출력)
- 세션 영속화 (SQLite, --resume native)
- 프로젝트 초기화 (preset pack: fullstack/gamedev/trading)

### 문제 해결

| 증상 | 원인 | 해결 |
|------|------|------|
| `path must be inside Path.home()` | 프로젝트가 home 밖 | `GOLEM_EXTRA_PROJECT_ROOTS` env 설정 |
| `forge.sh: $'\r': command not found` | CRLF 잔여 | `install.sh` 재실행 (CRLF 자동 정규화) |
| `No such file or directory: /c/Users/...` | 한글 username + Git Bash | `setup.ps1` 실행해 junction 자동 생성 |
| 채팅 응답 없음 | env 미설정 | `setup.ps1` 후 새 셸로 기동 |
| `[ERR] uv sync failed` | uv 미설치 | https://docs.astral.sh/uv/getting-started/installation/ |

---

*GolemGarden — AI는 널렸다. 우리는 장인을 만든다.*
