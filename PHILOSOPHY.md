# GolemGarden — 핵심 철학과 작업 규약

> *AI는 널렸다. 우리는 장인을 만든다.*

---

## 1. 핵심 철학

### 1.1 SOUL은 족쇄가 아니라 나침반

SOUL.md는 AI 에이전트의 능력을 **제한하지 않는다**.
OMC 에이전트는 이미 충분히 유능하다. SOUL은 그 능력의 **방향**만 잡아준다.

```
❌ 족쇄: "너는 Ryn이다. Spring Boot만 써라. 테스트 없으면 멈춰라."
   → 능력을 가두고, 프롬프트를 낭비하고, 성능을 저하시킴

✅ 나침반: "기술스택: Spring Boot 3.x. 우선순위: 테스트 > 속도."
   → 능력 100% 유지, 방향만 안내
```

SOUL.md는 에이전트의 **성격표**가 아니라 **프로젝트 매뉴얼**이다.
`personality` 필드는 사용자용 메모일 뿐, 프롬프트에 주입되지 않는다.

### 1.2 성장은 데이터로 증명한다

SOUL은 태스크를 수행할수록 **측정 가능한 방식으로** 성장한다.

- **growth-log**: 모든 태스크 결과를 JSONL로 불변 기록 (비용 포함)
- **랭크 시스템**: 태스크 횟수 + 무결함 연속으로 자동 승급
- **업적 뱃지**: 이정표마다 가시적인 보상
- **SOUL Memory**: 과거 실수를 기억하여 반복하지 않음
- **Skill Tree**: Senior부터 전문화 분기 선택

"느낌"이 아니라 "숫자"로 성장을 확인한다.

### 1.3 팀은 개인의 합보다 크다

GolemGarden의 가치는 개별 SOUL이 아니라 **팀 조합**에서 나온다.

- **Chemistry**: SOUL 쌍별 협업 점수를 추적하여 최적 팀 구성
- **Coordinator 프로토콜**: Nex(Director)는 코드를 직접 작성하지 않고 팀을 지휘
- **크로스 리뷰**: 다른 SOUL의 관점에서 검증하여 품질 보장
- **메일박스**: SOUL 간 비동기 통신으로 협업

### 1.4 OMC를 대체하지 않고 얹는다

GolemGarden은 독자 프레임워크가 아니다.
**oh-my-claudecode(OMC) 위에 올라타는 커스텀 레이어**다.

```
GolemGarden이 하는 것    ← SOUL 관리, 성장, 팀 역학
OMC가 하는 것            ← 에이전트 실행, 모델 라우팅, 병렬화
Claude Code가 하는 것    ← LLM 통신, 도구, 권한, UI
```

재발명하지 않는다. 각 레이어가 가장 잘하는 것에 집중한다.

### 1.5 비용은 투자이고, 추적 가능해야 한다

AI 에이전트 실행은 돈이 든다. GolemGarden은 비용을 숨기지 않고 추적한다.

- **토큰/USD 추적**: 모든 태스크에 비용 기록
- **수확체감 감지**: 3턴 연속 진전 없으면 자동 경고
- **예산 상한**: 토큰/USD 한도 초과 시 중단
- **Fork 캐시 최적화**: 병렬 실행 시 byte-identical prefix로 76% 절감
- **모델 라우팅**: haiku로 충분한 작업은 haiku에 배정

---

## 2. 작업 규약

### 2.1 SOUL 파일 규약

```yaml
---
name: Ryn                            # 고유 이름 (팀 내 유일)
role: backend-developer              # 역할 (soul_to_omc_agent 매핑)
rank: novice                         # 랭크 (novice→junior→senior→lead→master)
specialty: [spring-boot, mariadb]    # 전문 분야 (태스크 매칭용)
personality: 꼼꼼하고 보수적.         # 사용자 메모 (프롬프트 미주입!)
model: sonnet                        # 기본 모델
tools: [Read, Edit, Grep, Glob]      # 허용 도구 (rank 기반 점진적 확장)
maxTurns: 15                         # 최대 턴 수
isolation: none                      # 격리 모드 (none | worktree)
effort: medium                       # 모델 노력 수준
created: 2026-03-30
---
```

**절대 규칙**:
- SOUL 파일은 직접 Edit/Write하지 않는다 → `forge soul-create` 사용
- `.golem/souls/`(프로젝트)가 `souls/`(글로벌)보다 우선
- `personality`는 프롬프트에 주입되지 않는다

### 2.2 Coordinator 규약

Director(Nex)는 **절대 코드를 직접 작성하지 않는다**.

| 허용 | 금지 |
|------|------|
| Agent (SOUL 소환) | Edit (코드 수정) |
| SendMessage (통신) | Write (파일 생성) |
| TaskCreate (작업 생성) | Bash (명령 실행) |
| TaskStop (작업 중단) | NotebookEdit |
| Read, Grep, Glob (조회) | |

이것은 프롬프트 권고가 아니라 **시스템 레벨 강제**다 (`SOUL_DISALLOWED_TOOLS`).

**4단계 워크플로**:
1. **분석** — 작업을 이해하고 필요한 전문성 파악
2. **분배** — 최적의 SOUL 선택 (specialty + rank + chemistry)
3. **종합** — SOUL 결과를 검토하고 통합
4. **검증** — QA SOUL에게 리뷰 위임

### 2.3 랭크와 권한 규약

| 랭크 | 태스크 조건 | 도구 | 리뷰 | 격리 | 전문화 |
|------|-----------|------|------|------|--------|
| **Novice** | 시작 | Read, Edit, Grep, Glob | 필수 | 없음 | 불가 |
| **Junior** | 10회 | + Write, Bash | 필수 | 없음 | 불가 |
| **Senior** | 50회 + 무결함10연속 | + Agent, WebFetch | 선택 | worktree | **가능** |
| **Lead** | 100회 | + SendMessage | 면제 | worktree | 가능 |
| **Master** | 200회 | + TaskCreate (전체) | 면제 | worktree | 가능 |

**승급은 자동이다**. `forge log-add` 후 조건 충족 시 자동 체크.

### 2.4 도구 성격 규약

모든 도구는 4가지 성격 속성을 가진다:

| 속성 | 의미 | 예시 |
|------|------|------|
| `isReadOnly` | 상태 변경 없음 | Read, Grep, Glob |
| `isConcurrencySafe` | 동시 실행 안전 | Read, Agent, SendMessage |
| `isDestructive` | 되돌릴 수 없는 변경 | Bash (rm 가능) |
| `isIdempotent` | 반복 실행해도 같은 결과 | Read, Write, TaskStop |

**Coordinator 병렬화 판단**:
- 두 SOUL 모두 readOnly 도구만 → 자유롭게 병렬 (`safe`)
- 쓰기 도구 포함 → 파일 영역 분리 필요 (`caution`)
- 파괴적 도구 포함 → worktree 격리 또는 직렬 (`unsafe`)

### 2.5 에러 복구 규약

**Withholding 원칙**: 모든 에러를 모델에 보고하지 않는다.

```
도구 실행 에러 발생
  ├── 일시적 에러? (timeout, rate_limit, 429, 503)
  │   └── 보류(withhold) → 에이전트 레벨 자동 재시도
  ├── 자동 복구 가능? (file_not_found → 검색, permission → fallback)
  │   └── 보류(withhold) → 대체 경로 시도
  └── 복구 불가? (syntax_error, type_error, logic_error)
      └── 보고(report) → 모델에 전달
```

**3단계 실패 복구 프로토콜**:
1. **재시도** — 같은 SOUL에 실패 원인 주입 후 재시도 (최대 2회)
2. **위임** — 다른 SOUL에 specialty 매칭으로 위임
3. **에스컬레이션** — Director에게 보고, 사용자에게 최종 판단 요청

### 2.6 비용 규약

- 모든 태스크에 `tokens_in`, `tokens_out`, `cost_usd` 기록
- **수확체감 감지**: 3턴 연속 출력 500토큰 미만 → 자동 경고
- **예산 상한**: 세션 토큰 50만 / USD $10 (환경변수로 조정)
- **Fork 캐시**: 병렬 SOUL 소환 시 공통 프롬프트 접두사 byte-identical 유지
- **모델 효율**: haiku로 충분한 작업(QA, 분석)은 haiku SOUL에 배정

### 2.7 통신 규약

**메일박스 메시지 타입**:

| 타입 | 방향 | 설명 |
|------|------|------|
| `task_assign` | Coordinator → Worker | 태스크 배정 |
| `task_done` | Worker → Coordinator | 완료 보고 |
| `review_request` | Worker → Reviewer | 리뷰 요청 |
| `dependency_ready` | Worker → Worker | 의존성 완료 알림 |
| `broadcast` | 1 → 전체 | 전체 공지 |
| `escalation` | Worker → Coordinator | 에러 에스컬레이션 |
| `shutdown_request` | Coordinator → 전체 | 팀 종료 요청 |
| `shutdown_response` | Worker → Coordinator | 종료 확인 |
| `budget_warning` | System → 전체 | 예산 경고 |
| `plan_approval` | Coordinator → User | 계획 승인 요청 |

### 2.8 세션 규약

- 모든 `forge build`는 세션을 생성한다
- 세션에는 SOUL별 상태와 트랜스크립트가 기록된다
- `forge session resume`으로 중단된 작업을 재개할 수 있다
- 세션 종료 시 자동으로 **Retrospective(회고)** 생성을 권고한다

### 2.9 Knowledge Sync 규약

**지식 승격 5단계 체크리스트** (Sage 심사):

1. **오염 체크** — 특정 프로젝트에서만 유효한가? (포트, 경로, 환경변수)
2. **충돌 체크** — 기존 글로벌 지식과 모순되는가?
3. **품질 체크** — 다른 프로젝트에서도 바로 적용 가능한가?
4. **중복 체크** — 이미 글로벌에 비슷한 지식이 있는가?
5. **구체성 체크** — 구체적 기술/수치/패턴이 포함되어 있는가?

5개 모두 통과 → 글로벌 승격 (promote)
1~2개 불확실 → 보류 (hold)
프로젝트 전용/추상적/충돌 → 기각 (reject)

---

## 3. GolemGarden만의 차별점

Claude Code나 OMC에는 없고, GolemGarden만 가진 것들:

### 3.1 성장하는 에이전트

| 기능 | 효과 |
|------|------|
| **Rank System** | Novice→Master 5단계, 태스크 실적으로 자동 승급 |
| **Growth Log** | 모든 활동을 불변 기록 (비용 포함) |
| **SOUL Memory** | 과거 교훈을 기억하여 같은 실수 반복 방지 |
| **Skill Tree** | Senior부터 전문 분야 선택 → 범용보다 깊은 전문성 |
| **Achievement** | 15개 뱃지로 성장의 가시화 |

### 3.2 팀 역학

| 기능 | 효과 |
|------|------|
| **Chemistry** | SOUL 쌍별 S~F 점수 → 데이터 기반 팀 최적화 |
| **Domain Pack** | 미리 구성된 팀 번들 (fullstack, gamedev, trading) |
| **Coordinator Protocol** | Director의 4단계 워크플로 공식화 |
| **Cross Review** | SOUL 전문성 기반 크로스 리뷰 |
| **Retrospective** | 매 빌드 후 자동 회고 → 팀이 점점 개선됨 |

### 3.3 프로젝트 적응

| 기능 | 효과 |
|------|------|
| **Project DNA** | 프로젝트 지문 자동 생성 → SOUL 이동 적응도 측정 |
| **Knowledge Sync** | Sage 5단계 심사 → 오염 없는 글로벌 지식 승격 |
| **Portability** | SOUL + 이력 + 랭크를 프로젝트 간 이동 |

### 3.4 안전과 효율

| 기능 | 효과 |
|------|------|
| **Tool Character** | 도구 성격 기반 병렬 안전성 자동 판단 |
| **Budget Tracker** | 수확체감 감지 + 예산 상한 + 자동 중단 |
| **Withholding** | 일시적 에러 자동 복구, 모델 컨텍스트 오염 방지 |
| **Fork Cache** | byte-identical prefix로 API 비용 76% 절감 |
| **Hook Guards** | growth-log/mailbox 직접 수정 차단 |

---

## 4. 아키텍처 레이어

```
┌──────────────────────────────────────────────────────┐
│              GolemGarden 고유 레이어                    │
│                                                      │
│  ┌─ 성장 엔진 ──────────────────────────────────────┐│
│  │ Rank │ Memory │ Skill Tree │ Achievement │ Growth ││
│  └──────────────────────────────────────────────────┘│
│  ┌─ 팀 역학 ──────────────────────────────────────┐  │
│  │ Chemistry │ Coordinator │ Review │ Retrospective│  │
│  └──────────────────────────────────────────────────┘│
│  ┌─ 프로젝트 적응 ──────────────────────────────────┐│
│  │ Project DNA │ Knowledge Sync │ Portability       ││
│  └──────────────────────────────────────────────────┘│
│  ┌─ 안전과 효율 ──────────────────────────────────┐  │
│  │ Budget │ Tool Character │ Withholding │ Fork $  │  │
│  └──────────────────────────────────────────────────┘│
├──────────────────────────────────────────────────────┤
│              GolemGarden 인프라 레이어                  │
│  SOUL Parser │ Prompt Builder │ Mailbox │ Session    │
│  Error Recovery │ Worktree │ Hook Guards             │
├──────────────────────────────────────────────────────┤
│              oh-my-claudecode (OMC)                   │
│  32 agents │ 5 exec modes │ Model routing │ HUD      │
├──────────────────────────────────────────────────────┤
│              Claude Code CLI                         │
│  LLM │ Tools │ Permission │ Bridge │ UI              │
└──────────────────────────────────────────────────────┘
```

---

## 5. 수치로 보는 GolemGarden

| 항목 | 수치 |
|------|------|
| lib 모듈 | **21개** |
| SOUL 글로벌 | **12개** (3개 도메인 팩) |
| Hook 스크립트 | **4개** |
| 업적 정의 | **15개** |
| SOUL frontmatter 필드 | **11개** |
| 메일박스 메시지 타입 | **10종** |
| 도구 성격 DB | **13종** |
| 전문화 브랜치 | **역할별 3개** |
| forge 명령 | **50+ 서브커맨드** |

---

*GolemGarden — AI는 널렸다. 우리는 장인을 만든다.*
