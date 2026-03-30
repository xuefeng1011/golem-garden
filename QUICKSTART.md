# GolemGarden 퀵 가이드

> AI 에이전트를 심고, 키우고, 팀으로 엮는 정원

---

## 0. 이것부터 이해하세요

### 전체 워크플로우: Claude Code CLI 안에서 한 마디로 끝

```
┌──────────────────────────────────────────────────────────┐
│  Claude Code CLI (대화창)                                  │
│                                                          │
│  사용자: forge build: 인증 API + 로그인 화면                 │
│                                                          │
│  ┌──── GolemGarden 스킬 (자동 실행) ────────────────────┐  │
│  │                                                      │  │
│  │  ① forge-board.md 읽기 → 팀 파악                     │  │
│  │  ② Nex(Director) SOUL 로드 → 태스크 분석              │  │
│  │  ③ "Backend → Ryn, Frontend → Kai" 분배               │  │
│  │  ④ 각 SOUL 컨텍스트를 OMC Agent에 주입                 │  │
│  │     ┌─────────────────┐  ┌──────────────────┐        │  │
│  │     │ Ryn(executor)   │  │ Kai(designer)    │        │  │
│  │     │ Spring Boot     │  │ React+TS         │        │  │
│  │     │ 컨텍스트 주입    │  │ 컨텍스트 주입     │        │  │
│  │     │ → 코드 생성     │  │ → 코드 생성      │        │  │
│  │     └─────────────────┘  └──────────────────┘        │  │
│  │         (병렬 실행)            (병렬 실행)              │  │
│  │                                                      │  │
│  │  ⑤ 완료 → growth-log 자동 기록                        │  │
│  │  ⑥ Novice이므로 → 자동 리뷰 트리거                    │  │
│  │  ⑦ Zen(QA)이 리뷰 → pass → 무결함 카운트 +1          │  │
│  │                                                      │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                          │
│  AI: "완료! Ryn: 인증 API (8파일), Kai: 로그인 (3파일)      │
│       리뷰: Zen → Pass. Ryn 무결함 4연속!"                  │
└──────────────────────────────────────────────────────────┘
```

**핵심: 사용자는 Claude Code 대화창에서 한 줄만 입력합니다.**
나머지(팀 분배, SOUL 컨텍스트 주입, 실행, 기록, 리뷰)는 전부 자동입니다.

### 어디서 뭘 치면 되나요?

| 상황 | 어디서 | 뭘 치면 |
|------|--------|--------|
| **팀 구성** | Claude Code 대화창 | `forge-init: 풀스택 웹앱, Spring Boot + React` |
| **작업 지시** | Claude Code 대화창 | `forge build: 사용자 인증 API + 로그인 화면` |
| **간단한 작업** | Claude Code 대화창 | `forge quick: README 업데이트` |
| **특정 SOUL에게** | Claude Code 대화창 | `forge assign ryn: JWT 미들웨어 구현` |
| **코드 리뷰** | Claude Code 대화창 | `forge review ryn` |
| **상태 확인** | Claude Code 대화창 | `forge status` |
| **SOUL 추가** | Claude Code 대화창 | `forge soul-create devops-engineer` |
| **팩 설치** | Claude Code 대화창 | `forge pack install trading` |

**bash 터미널이 아닙니다. Claude Code 대화창에서 치는 겁니다.**
Claude가 스킬을 인식하고 `forge.sh` + OMC Agent를 자동으로 호출합니다.

### 수동으로도 쓸 수 있나요?

네. 디버그나 확인 용도로 bash에서 직접 쓸 수도 있습니다:
```bash
# 팀 상태 확인
bash forge.sh status

# 프롬프트 미리보기 (어떤 컨텍스트가 주입되는지 확인)
bash forge.sh prompt ryn "인증 API 구현"

# 성장 기록 수동 추가
bash forge.sh log-add ryn "JWT 구현" success 8 15
```

하지만 **일반적인 사용은 Claude Code 대화창에서** 합니다.

---

## 1. 준비물

| 항목 | 필수 여부 | 설명 |
|------|----------|------|
| **Claude Code CLI** | 필수 | Claude Max ($100/월) 구독 필요 |
| **oh-my-claudecode (OMC)** | 필수 | 멀티 에이전트 오케스트레이션 레이어 |
| **Git Bash** | 필수 (Windows) | forge CLI가 bash 기반 |
| **Git** | 권장 | 버전 관리 및 협업 |

### 1-1. Claude Code 설치 확인

```bash
claude --version
```

### 1-2. OMC 설치 확인

Claude Code 안에서:
```
/plugin marketplace add https://github.com/Yeachan-Heo/oh-my-claudecode
/plugin install oh-my-claudecode
```

설치 확인: Claude Code 대화에서 `setup omc` 또는 `/oh-my-claudecode:omc-setup` 실행.

---

## 2. GolemGarden 설치

```bash
# 리포 클론
git clone https://github.com/your-org/golem-garden.git
cd golem-garden

# 설치 (SOULs + 스킬을 ~/.claude/에 복사)
bash install.sh
```

설치 후 확인:
```bash
bash forge.sh status
```

출력 예시:
```
=== GolemGarden SOULs ===

Name       Role                   Rank       Model    Specialty
----       ----                   ----       -----    ---------
Nex        director               junior     opus     architecture, task-decomposition...
Ryn        backend-developer      novice     sonnet   spring-boot, mariadb, rest-api...
```

---

## 새 프로젝트에서 GolemGarden 사용하기 (전체 프로세스)

### 전체 흐름도

```
[1단계] 프로젝트 생성     →  [2단계] 팀 구성        →  [3단계] 개발
새 프로젝트 폴더 만들기       forge-init 으로           forge build 로
Claude Code 열기              SOUL 팀 자동 구성          작업 지시하면 끝

   ↓                           ↓                        ↓
[4단계] 리뷰              →  [5단계] 성장            →  [6단계] 반복
자동 크로스 리뷰              SOUL 경험 누적              팀이 점점 성장
Novice는 리뷰 필수            랭크 자동 승급              Senior가 되면 자율 실행
```

### 1단계: 새 프로젝트 시작

프로젝트 폴더를 만들고 Claude Code를 엽니다.

```bash
mkdir my-new-project
cd my-new-project
git init
claude          # Claude Code 실행
```

### 2단계: 팀 구성 (Claude Code 대화창에서)

```
You: forge-init: 풀스택 웹앱, Spring Boot + React + MariaDB
```

이 한 마디로 다음이 자동 실행됩니다:
- 프로젝트 유형 분석 → 풀스택 팩 매칭
- Nex(Director), Ryn(Backend), Kai(Frontend), Zen(QA), Bolt(DevOps) 배치
- 각 SOUL에 기술스택 컨텍스트 주입 (Spring Boot, React 등)
- forge-board.md 생성 (팀 구성표)

**다른 프로젝트 유형 예시:**
```
You: forge-init: 모바일 게임, Cocos Creator + TypeScript
You: forge-init: 주식 분석 봇, Python + pandas
You: forge-init: REST API 서버, Node.js + Express + PostgreSQL
```

### 3단계: 개발 (한 마디로 작업 지시)

```
You: forge build: 사용자 인증 API + 로그인 화면
```

자동으로 일어나는 일:
1. Nex(Director)가 태스크 분석
2. "Backend API → Ryn, Frontend UI → Kai" 분배
3. Ryn의 SOUL 컨텍스트(Spring Boot, Clean Architecture 등)를 주입하여 실행
4. Kai의 SOUL 컨텍스트(React, TypeScript 등)를 주입하여 실행
5. **병렬 실행** — 둘 다 동시에 코드 생성

**다양한 작업 지시 방법:**
```
# 대규모 작업 (병렬 실행)
You: forge build: 결제 시스템 + 주문 관리 + 알림

# 간단한 작업 (단독 실행)
You: forge quick: README 업데이트

# 특정 SOUL에게 직접
You: forge assign ryn: JWT 토큰 갱신 로직 수정

# 리드 지정
You: forge build: 마이페이지 기능, kai 리드
```

### 4단계: 리뷰 (자동)

3단계 완료 후 Novice/Junior SOUL이면 **자동으로 리뷰가 트리거**됩니다.

```
(자동 실행됨 — 사용자가 별도로 칠 필요 없음)
→ Zen(QA)이 Ryn의 코드 리뷰
→ 결과: Pass / Fail
→ growth-log에 자동 기록
```

수동으로 리뷰를 요청할 수도 있습니다:
```
You: forge review ryn
You: forge review kai zen          # Kai의 코드를 Zen이 리뷰
```

### 5단계: 성장 확인

```
You: forge status
```

출력:
```
Name       Role                Rank       Tasks   Rate    Streak
Ryn        backend-developer   novice     5건    100%    5연속
Kai        frontend-developer  novice     3건    100%    3연속
Zen        qa-tester           novice     4건    100%    4연속
```

10건 완료 시 자동 승급:
```
[rank] Ryn: 승급 가능! novice → junior (태스크 10건 완료)
```

### 6단계: 계속 반복

```
You: forge build: 상품 목록 API + 상품 카드 컴포넌트
You: forge build: 장바구니 기능
You: forge build: 결제 연동
...
```

SOUL은 매번 성장합니다:
- 태스크 이력 누적 → 성공률, 무결함 연속 기록
- 랭크 승급 → 권한 확대 (Senior가 되면 자율 실행, 리뷰 면제)
- 프로젝트를 옮겨도 이력이 따라감

### 한눈에 보는 일상 워크플로우

```
아침: Claude Code 열고

You: forge status                              ← 팀 상태 확인
You: forge build: 오늘 할 기능들                  ← 작업 지시
(코드 자동 생성 + 리뷰 자동 실행)
You: forge build: 버그 수정 3건                   ← 추가 작업
You: forge status                              ← 성장 확인

끝. 이게 전부입니다.
```

### 프로젝트 간 SOUL 이동

다른 프로젝트에서 키운 SOUL을 가져올 수도 있습니다:
```
You: forge import /path/to/old-project ryn     ← Senior Ryn 가져오기
```

Senior Ryn은 이전 프로젝트의 50건+ 이력과 함께 들어와서,
새 프로젝트에서도 아키텍처 제안, 자율 실행이 가능합니다.

---

## 3. 첫 번째 해볼 것: 5분 체험

### Step 1: 현재 팀 확인

```bash
bash forge.sh souls
```

### Step 2: QA SOUL 추가 (프리셋에서 원클릭 생성)

```bash
bash forge.sh soul-create qa-tester
# → Zen (qa-tester, haiku) 자동 생성
```

### Step 3: 프론트엔드 SOUL 추가

```bash
bash forge.sh soul-create frontend-developer
# → Kai (frontend-developer, sonnet) 자동 생성
```

### Step 4: 팀 상태 확인

```bash
bash forge.sh status
```

### Step 5: 프롬프트 주입 미리보기

```bash
bash forge.sh prompt ryn "사용자 인증 API 구현"
```

이것이 OMC 에이전트에 주입되는 실제 컨텍스트입니다.

---

## 4. 핵심 워크플로우

### 4-1. 프로젝트 시작 (팀 구성)

```bash
# 방법 A: 프리셋으로 개별 생성
bash forge.sh soul-create backend-developer      # Ryn 생성
bash forge.sh soul-create frontend-developer     # Kai 생성
bash forge.sh soul-create qa-tester              # Zen 생성
bash forge.sh soul-create devops-engineer        # Bolt 생성

# 방법 B: 도메인 팩 한번에 설치
bash forge.sh pack install fullstack
# → Kai, Zen, Bolt 한번에 설치 + forge-board 포함

# 방법 C: 커스텀 SOUL 직접 생성
bash forge.sh soul-custom Aria data-engineer "spark, airflow, dbt" "파이프라인의 여신"
```

### 4-2. 태스크 실행 (프롬프트 주입)

```bash
# Director(Nex)에게 태스크 분배 의뢰
bash forge.sh prompt-director "사용자 인증 API + 로그인 화면 구현"

# 특정 SOUL에게 직접 태스크 지시
bash forge.sh prompt ryn "JWT 인증 미들웨어 구현"
bash forge.sh prompt kai "로그인 폼 컴포넌트 구현"
```

생성된 프롬프트를 Claude Code의 Agent tool에 전달하면 SOUL 컨텍스트가 주입된 상태로 실행됩니다.

### 4-3. 작업 완료 후 기록

```bash
# 성장 기록 추가
bash forge.sh log-add ryn "JWT 인증 구현" success 8 15
bash forge.sh log-add kai "로그인 폼 구현" success 3 6

# 자동 랭크 체크 (10건 완료 시 novice → junior 승급)
bash forge.sh rank ryn
```

### 4-4. 크로스 리뷰

```bash
# Ryn의 코드를 자동 선정된 리뷰어가 리뷰
bash forge.sh review ryn

# 특정 리뷰어 지정
bash forge.sh review ryn zen "AuthController"

# 리뷰 결과 기록
bash forge.sh review-record ryn zen "AuthController" pass 0 none
# → pass(무결함) 연속 카운트 누적 → 랭크 승급 조건에 반영
```

---

## 5. 명령어 전체 레퍼런스

### 상태 확인

| 명령어 | 설명 |
|--------|------|
| `forge status` | 팀 전체 상태 (SOUL 목록 + 성장 대시보드) |
| `forge souls` | 등록된 SOUL 목록만 |
| `forge dashboard` | 성장 대시보드 (태스크/성공률/연속 무결함) |
| `forge rank-board` | 랭크 대시보드 (승급 가능 여부 포함) |
| `forge review-status` | 리뷰 상태 대시보드 |
| `forge portability` | SOUL 이동 이력 |

### 프롬프트 생성

| 명령어 | 설명 |
|--------|------|
| `forge prompt <name> <task>` | SOUL 컨텍스트 주입 프롬프트 생성 |
| `forge prompt-director <task>` | Director가 팀 분배하는 프롬프트 |
| `forge prompt-review <reviewer> <worker> <target>` | 리뷰어 프롬프트 생성 |

### 성장 관리

| 명령어 | 설명 |
|--------|------|
| `forge log <name>` | SOUL 성장 기록 조회 |
| `forge log-add <name> <task> <result> [files] [tests]` | 성장 기록 추가 |
| `forge rank <name>` | 랭크 확인 + 승급 조건 체크 |
| `forge promote <name>` | 랭크 승급 실행 (조건 충족 시) |

### 리뷰

| 명령어 | 설명 |
|--------|------|
| `forge review <worker> [reviewer] [target]` | 크로스 리뷰 (리뷰어 자동/수동) |
| `forge review-record <worker> <reviewer> <target> <result> [issues] [severity]` | 리뷰 결과 기록 |
| `forge review-auto <worker> <task>` | rank 기반 자동 리뷰 트리거 |

### SOUL 생성

| 명령어 | 설명 |
|--------|------|
| `forge soul-create <role> [name] [model]` | 프리셋 기반 생성 |
| `forge soul-custom <name> <role> <specialties> [personality] [model]` | 커스텀 생성 |
| `forge soul-presets` | 프리셋 목록 (7개 역할) |
| `forge soul-create-all` | 전체 프리셋 한번에 생성 |

### 도메인 팩

| 명령어 | 설명 |
|--------|------|
| `forge pack list` | 사용 가능한 팩 목록 |
| `forge pack install <name>` | 팩 설치 (SOULs + forge-board) |
| `forge pack uninstall <name>` | 팩 제거 (growth-log 보존) |
| `forge pack info <name>` | 팩 상세 정보 |

사용 가능한 팩: `gamedev`, `trading`, `fullstack`

### 포터빌리티 (프로젝트 간 이동)

| 명령어 | 설명 |
|--------|------|
| `forge export <name> <target_dir>` | SOUL + 이력 내보내기 |
| `forge import <source_dir> <name>` | SOUL + 이력 가져오기 (로그 병합) |
| `forge export-pack <pack_name> [target_dir]` | 전체 팀 팩으로 내보내기 |
| `forge import-pack <pack_dir>` | 팩 가져오기 |

---

## 6. 랭크 시스템

SOUL은 태스크를 수행할수록 성장합니다.

| 랭크 | 승급 조건 | 권한 |
|------|----------|------|
| **Novice** | 생성 직후 | 단일 파일 수정, 리뷰 필수 |
| **Junior** | 태스크 10회 완료 | 멀티파일 수정, 테스트 작성 |
| **Senior** | 태스크 50회 + 무결함 10연속 | 아키텍처 제안, 자율 실행 |
| **Lead** | 태스크 100회 + 멘토링 | 팀 오케스트레이션 |
| **Master** | 태스크 200회 + 커뮤니티 검증 | 모든 권한, 리뷰 면제 |

```bash
# 랭크 확인
bash forge.sh rank ryn

# 승급 (조건 충족 시 자동)
bash forge.sh promote ryn

# 랭크 대시보드
bash forge.sh rank-board
```

---

## 7. 도메인 팩 가이드

### 게임 개발 팩

```bash
bash forge.sh pack install gamedev
```

| SOUL | 역할 | 전문 분야 |
|------|------|----------|
| Sprite | 게임 디자이너 | 기획, 밸런스, 레벨 설계 |
| Pixel | 그래픽/UI | Canvas, 스프라이트, 애니메이션 |
| Glitch | 게임 로직 | 물리엔진, 충돌, 게임 루프 |

### 주식/크립토 분석 팩

```bash
bash forge.sh pack install trading
```

| SOUL | 역할 | 전문 분야 |
|------|------|----------|
| Oracle | 기술적 분석 | 차트 패턴, RSI/MACD, 백테스트 |
| Sentinel | 리스크 관리 | 포지션 사이징, 손절, MDD |
| Scout | 뉴스/센티먼트 | 크롤링, NLP, 소셜 트렌드 |

### 풀스택 웹앱 팩

```bash
bash forge.sh pack install fullstack
```

| SOUL | 역할 | 전문 분야 |
|------|------|----------|
| Kai | 프론트엔드 | React, TypeScript, Tailwind |
| Zen | QA/테스터 | Jest, Cypress, E2E |
| Bolt | DevOps | Docker, K8s, GitHub Actions |

---

## 8. 프로젝트 간 SOUL 이동

한 프로젝트에서 키운 SOUL을 다른 프로젝트로 옮길 수 있습니다.
성장 이력(growth-log)이 함께 이동하므로 랭크가 유지됩니다.

```bash
# 내보내기 (SOUL + 성장 이력)
bash forge.sh export ryn /path/to/new-project

# 가져오기 (로그 자동 병합, 높은 랭크 유지)
bash forge.sh import /path/to/source ryn

# 전체 팀 내보내기/가져오기
bash forge.sh export-pack my-team /path/to/backup
bash forge.sh import-pack /path/to/backup/soul-pack-my-team
```

---

## 9. OMC 연동 구조

GolemGarden은 OMC를 대체하지 않습니다. OMC 위에서 **방향**만 잡아줍니다.

```
사용자: "forge build: 인증 API 만들어줘"
  ↓
① forge-board.md에서 팀 로드 → Nex, Ryn, Zen
  ↓
② Nex(Director) → 태스크 분석 → Ryn 배정
  ↓
③ Ryn의 SOUL.md 로드 → OMC executor에 컨텍스트 주입
   "기술스택: Spring Boot 3.x, MariaDB
    우선순위: 에러 핸들링 > 기능 완성
    이전 이력: 15건, 성공률 93%"
  ↓
④ OMC가 실행 (executor 에이전트, sonnet 모델)
  ↓
⑤ 완료 → growth-log 기록 → 랭크 체크
```

**SOUL = 족쇄가 아니라 나침반.** OMC 에이전트의 능력은 100% 유지, 방향만 안내.

---

## 10. FAQ

### Q: SOUL 없이도 OMC는 쓸 수 있나요?
**A:** 네. OMC는 독립적으로 동작합니다. GolemGarden은 SOUL 컨텍스트를 얹어서 "누가, 어떤 경험으로" 작업하는지를 추가하는 레이어입니다.

### Q: SOUL의 personality는 프롬프트에 주입되나요?
**A:** 아닙니다. personality는 사용자가 읽는 메모일 뿐입니다. 주입되는 것은 `프로젝트 컨텍스트`, `전문 지식`, `성장 이력 요약`입니다.

### Q: 비용은 얼마인가요?
**A:** Claude Max 구독 $100/월만 있으면 됩니다. OMC, GolemGarden 모두 무료(오픈소스)입니다.

### Q: SOUL을 삭제하면 이력도 사라지나요?
**A:** `pack uninstall`로 제거해도 `growth-log/`는 보존됩니다. 재설치 시 이력이 이어집니다.

### Q: 랭크를 수동으로 올릴 수 있나요?
**A:** `souls/{name}.md`의 `rank:` 필드를 직접 수정하면 됩니다. 다만 growth-log 기반 자동 승급을 권장합니다.

---

## 빠른 시작 치트시트

```bash
# 설치
bash install.sh

# 팀 구성 (풀스택 예시)
bash forge.sh pack install fullstack

# 팀 확인
bash forge.sh status

# 태스크 실행
bash forge.sh prompt ryn "JWT 인증 API 구현"
bash forge.sh prompt-director "결제 시스템 전체 구현"

# 결과 기록
bash forge.sh log-add ryn "JWT 인증" success 8 15

# 리뷰
bash forge.sh review ryn
bash forge.sh review-record ryn zen "AuthController" pass 0

# 랭크 확인
bash forge.sh rank-board

# 팀 백업
bash forge.sh export-pack my-team ./backup
```

---

*GolemGarden — AI는 널렸다. 우리는 장인을 만든다.*
