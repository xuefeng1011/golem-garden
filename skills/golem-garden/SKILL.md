---
name: golem-garden
description: GolemGarden 메인 라우터. "forge", "포지", "forje" 및 SOUL 관련 명령(빌드/리뷰/상태/초기화/랭크 등)을 처리한다.
trigger: forge, 포지, forje, foge
---

# GolemGarden — 실행 스킬

사용자가 "forge" 관련 입력을 하면 이 스킬이 트리거된다.

## 입력 인식 규칙 (Fuzzy Matching)

사용자는 자연어로 입력하므로 다양한 변형을 모두 같은 명령으로 인식한다.
**대소문자 무시, 구두점 무시, 띄어쓰기 유연하게 처리.**

### forge-init (프로젝트 초기화)

아래 입력은 모두 `forge-init` 스킬을 실행한다:
```
forge-init: 풀스택 웹앱
forge init: 풀스택 웹앱
forge init 풀스택 웹앱
forge-init 풀스택
forje init
포지 초기화
포지 init
forge 초기화
포지 셋업
forge setup team
forge 팀 구성
forge 팀구성
forge 시작
포지 시작
forge-init              ← 설명 없이도 OK (자동 스캔)
```

### forge build (팀 빌드 — 병렬 실행)

아래 입력은 모두 `forge-team` 스킬 (ultrapilot 모드)을 실행한다:
```
forge build: 인증 API 만들어줘
forge build 인증 API
forge 빌드: 로그인 기능
forge 빌드 인증
포지 빌드: 결제 시스템
forge 만들어줘: 인증 API + 로그인
forje build
포지 빌드
```

### forge mission (단일 목표 완주 — 자율 실행)

아래 입력은 모두 `forge-mission` 스킬을 실행한다:
```
forge mission: 로그인 API 완성해줘
forge mission 결제 플로우 완주
포지 미션: 검색 기능
forge 미션 대시보드 완성
끝까지 해줘: 회원가입
완주: 알림 시스템
하나의 목적으로: 마이그레이션
하나의 목표 완주: 리팩터링
```

### forge quick (간단한 작업 — 단독 실행)

```
forge quick: README 수정
forge quick README
forge 퀵: 설정 변경
포지 퀵
forge 간단: 타이포 수정
forge 빠르게: 주석 추가
```

### forge assign (특정 SOUL에게 지정)

```
forge assign ryn: JWT 구현
forge ryn: JWT 구현               ← SOUL 이름만 써도 인식
포지 ryn: JWT
forge assign kai 로그인 화면
ryn한테: API 만들어줘              ← SOUL 이름 + "한테" 패턴
ryn에게: 인증 처리
kai한테 로그인 폼 만들어줘
```

**SOUL 이름 인식**: 등록된 SOUL 이름(nex, ryn, kai, zen, bolt, glitch, pixel, sprite, oracle, sentinel, scout)이
입력에 포함되어 있고 태스크 설명이 따라오면 → `forge assign`으로 처리.

### forge review (크로스 리뷰)

```
forge review ryn
forge review
forge 리뷰: ryn
forge 리뷰
포지 리뷰
forge 코드리뷰
forge 검토
리뷰해줘
코드 리뷰해줘
ryn 리뷰해줘
```

### forge status (상태 확인)

```
forge status
forge 상태
포지 상태
포지 스테이터스
forge 현황
팀 상태
soul 상태
SOUL 목록
```

### forge rank (랭크 확인)

```
forge rank ryn
forge 랭크 ryn
ryn 랭크
ryn 레벨
포지 랭크
```

### forge soul-create (SOUL 생성)

```
forge soul-create backend-developer
forge 소울 생성 백엔드
포지 소울 만들기
새 SOUL 만들어줘 QA
SOUL 추가: devops
에이전트 추가: 프론트엔드
```

### forge pack (도메인 팩)

```
forge pack install fullstack
forge pack list
forge 팩 설치 풀스택
포지 팩 목록
게임 팩 설치
트레이딩 팩 설치해줘
```

### forge studio (독립 플로우 스튜디오)

아래 입력은 모두 `forge-studio` 스킬을 실행한다:
```
forge studio: 시장조사 자동화
포지 스튜디오
스튜디오 만들어줘
독립 플로우 만들고 싶어
나만의 플로우 짜고 싶어
flow studio
프로젝트 밖에서 돌아가는 에이전트 팀 만들어줘
소설 쓰는 에이전트 팀 꾸리고 싶어
```

## 라우팅 판단 로직

**이 메인 라우터는 사용자 입력을 분석하여 올바른 서브스킬로 디스패치한다.**
**서브스킬(forge-init, forge-team 등)이 직접 트리거될 수도 있으므로, 이 라우터는 퍼지 매칭/오타 처리/모호성 해소 역할에 집중한다.**

사용자 입력을 받으면 다음 순서로 판단한다:

### 1. SOUL/에이전트 생성 요청 감지 (최우선)

입력에 `soul`, `소울`, `에이전트` + `만들어`, `생성`, `추가`, `만들기` 조합이 있으면:
→ **forge-soul 스킬** 실행 (대화형 문진 생성기)

예: "에이전트 만들어줘", "새 SOUL 추가", "소울 생성: 백엔드"

### 2. 키워드 매칭

| 우선순위 | 키워드 | 동작 |
|---------|--------|------|
| 1 | `init`, `초기화`, `셋업`, `setup`, `시작`, `팀 구성` | → forge-init 스킬 |
| 2 | `build`, `빌드`, `구현`, `개발` | → forge-team (ultrapilot) |
| 2.5 | `mission`, `미션`, `끝까지`, `완주`, `하나의 목적`, `하나의 목표` | → forge-mission (단일 목표 완주) |
| 2.6 | `studio`, `스튜디오`, `독립 플로우`, `나만의 플로우` | → forge-studio (독립 플로우 스튜디오) |
| 3 | `quick`, `퀵`, `간단`, `빠르게` | → forge-team (autopilot) |
| 4 | `assign` 또는 SOUL이름 + 태스크 | → forge-team (수동) |
| 5 | `review`, `리뷰`, `검토`, `코드리뷰` | → forge-review |
| 6 | `sync`, `동기화`, `지식`, `승격` | → forge-sync |
| 7 | `status`, `상태`, `현황`, `목록` | → forge status (bash 직접 실행) |
| 8 | `rank`, `랭크`, `레벨`, `승급` | → forge rank (bash 직접 실행) |
| 9 | `pack`, `팩` | → forge pack (bash 직접 실행) |
| 10 | `mailbox`, `메일박스`, `메시지`, `수신함` | → forge mailbox (bash 직접 실행) |
| 11 | `session`, `세션`, `resume`, `재개` | → forge session (bash 직접 실행) |
| 12 | `recover`, `복구`, `에러복구` | → forge mission run (결정론 재시도 루프) / forge recover-history (이력) |
| 13 | `cost`, `비용`, `토큰` | → forge dashboard --cost (bash 직접 실행) |
| 14 | `worktree`, `격리`, `isolation` | → forge worktree (bash 직접 실행) |
| 15 | `doctor`, `진단`, `헬스체크`, `점검` | → forge doctor (bash 직접 실행) |
| 16 | `verify`, `검증` | → forge verify (bash 직접 실행) |
| 17 | `explore`, `탐색`, `코드 컨텍스트` | → forge explore (bash 직접 실행) |
| 18 | `insights`, `인사이트`, `성과 분석`, `성과` | → forge insights (bash 직접 실행) |

**주의: `만들어`는 단독으로 forge-team 트리거가 아니다.**
- "만들어줘" + 코드/기능 설명 → forge-team (`forge build`)
- "만들어줘" + 에이전트/SOUL/역할 → forge-soul
- 판단 기준: 대상이 코드인가 SOUL인가

### 3. SOUL 이름 감지

입력에 등록된 SOUL 이름이 있고 + 태스크 설명이 있으면:
→ `forge assign {soul}: {태스크}`로 처리

### 4. 애매한 경우

위 규칙으로 판단이 안 되면 `forge triage`를 실행해 tier로 라우팅한다 (UX-EXPERT-PLAN C-1):
1. `GOLEM_PROJECT="$(pwd)" bash forge.sh triage "{task}"` 실행
2. 출력의 `TRIAGE tier=T{0|1|2}` 파싱
3. T0 → `forge quick: {task}`, T1 → `forge build: {task}`, T2 → `forge do "{task}"` (Nex 분해 → mission 생성, 실행은 사용자 승인 후 `forge mission run`)

트리아지로도 판단이 안 되면(예: 실행 오류) 기존 되묻기로 폴백한다:
```
"어떤 작업을 원하시나요?
1) 팀 구성 (forge-init)
2) 코드 생성 (forge build)
3) 리뷰 (forge review)
4) 상태 확인 (forge status)
5) SOUL 생성 (forge soul)"
```

## 직접 실행 명령어

### forge status / forge 상태
1. Bash로 `GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh status` 실행 (GOLEM_ROOT에서)
2. 결과를 사용자에게 보여줌

### forge souls / SOUL 목록
1. Bash로 `GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh souls` 실행

### forge rank {name}
1. Bash로 `GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh rank {name}` 실행

### forge dashboard
1. Bash로 `GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh dashboard` 실행

### forge soul-create {role}
1. Bash로 `GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh soul-create {role}` 실행
2. 생성된 SOUL 파일 내용을 사용자에게 보여줌

### forge pack install {name}
1. Bash로 `GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh pack install {name}` 실행

### forge mailbox {subcommand}
1. Bash로 `GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh mailbox {subcommand} {args}` 실행
2. 서브커맨드: `dashboard`, `send <from> <to> <type> <content>`, `broadcast <from> <content>`, `read <soul>`, `inbox <soul>`, `cleanup [days]`

### forge session {subcommand}
1. Bash로 `GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh session {subcommand} {args}` 실행
2. 서브커맨드: `create <task> <souls_csv>`, `status`, `list`, `resume`, `end [status]`

### forge 복구 (recover)
1. `forge recover` verb 는 제거됨 (무동작 명령이었음) — 재시도는 `forge mission run` 결정론 루프가 수행
2. 복구 이력 조회: `GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh recover-history {soul}` 실행

### forge dashboard --cost / forge 비용
1. Bash로 `GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh dashboard --cost` 실행

### forge worktree {subcommand}
1. Bash로 `GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh worktree {subcommand} {args}` 실행
2. 서브커맨드: `create <soul> [task]`, `merge <soul> [strategy]`, `cleanup <soul|all>`, `status`

### forge doctor / forge 진단
1. Bash로 `GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh doctor` 실행
2. 엔진 헬스체크 결과(claude CLI, SOUL, 디렉토리, 훅 상태)를 사용자에게 보여줌

### forge verify {target} [verifier_soul]
1. Bash로 `GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh verify {target} {verifier_soul}` 실행
2. 결정론적 테스트 + 독립 SOUL 심판(author≠verifier)의 결합 판정을 보여줌
3. 옵션: `--tests-only` (SOUL 호출 없이 테스트만)

### forge explore {keyword}
1. Bash로 `GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh explore {keyword}` 실행
2. grep-우선 코드 컨텍스트 수집 결과를 보여줌

### forge insights [soul]
1. Bash로 `GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh insights {soul}` 실행 (soul 생략 시 팀 전체)
2. 성과 패턴/추세/비용 효율 분석을 보여줌

## forge.sh 호출 규칙 (중요)

**모든 `GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh` 호출 시 반드시 `GOLEM_PROJECT`를 현재 작업 디렉토리로 설정하라:**

```bash
GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh {command} {args}
```

이렇게 하면:
- `.golem/souls/` 프로젝트 오버라이드가 적용됨
- `.golem/growth-log/` 프로젝트별 성장 기록에 저장됨
- `.golem/forge-board.md` 팀 구성이 읽힘

**절대 `GOLEM_PROJECT` 없이 호출하지 마라.** 글로벌에만 기록되고 프로젝트에 반영 안 됨.

## GOLEM_ROOT 결정

forge.sh는 `~/.claude/golem-garden/forge.sh` 에 설치되어 있다.
1. 글로벌 경로: `~/.claude/golem-garden/`
2. 프로젝트 경로: 현재 작업 디렉토리의 `.golem/`
3. 없으면 → 사용자에게 경로 물어보기

## 오타 / 오입력 처리

- `forje`, `foge`, `포지` → `forge`로 인식
- `buld`, `bild` → `build`로 인식
- `revew`, `rivew` → `review`로 인식
- `statsu`, `stauts` → `status`로 인식
- 의도를 파악할 수 없으면 "혹시 forge build를 말씀하신 건가요?" 식으로 되물어본다

## ⚠️ 필수 출력 규칙: 연관 작업 안내 (CRITICAL)

**모든 forge 명령 실행 후, 반드시 결과 마지막에 연관 작업 안내를 표시한다.**
이 규칙은 서브스킬(forge-init, forge-team, forge-review, forge-sync, forge-soul)과 직접 실행 명령 모두에 적용된다.
**생략하지 않는다. 조건부가 아니라 무조건이다.**

### 연관 작업 안내 맵

아래 표에 따라 실행된 명령의 다음 추천 작업을 안내한다:

| 실행된 명령 | 연관 작업 안내 |
|------------|--------------|
| `forge-init` | `forge build: {작업}` — 팀 빌드 시작 / `forge status` — 팀 현황 확인 |
| `forge build` | `forge review {soul}` — 코드 리뷰 / `forge status` — 결과 확인 / `forge dashboard --cost` — 비용 확인 |
| `forge mission` | `forge status` — 전체 현황 / `forge mission status {id}` — 미션 상세 / `forge review {soul}` — 산출물 리뷰 |
| `forge studio` | `forge studio status {dir}` — 스튜디오 상태 확인 / `forge studio agent-add ...` — 팀 보강 / `forge studio list` — 전체 스튜디오 |
| `forge quick` | `forge review` — 코드 리뷰 / `forge build: {작업}` — 팀 빌드로 확장 |
| `forge assign` | `forge review {soul}` — 코드 리뷰 / `forge mailbox inbox {soul}` — 메일 확인 |
| `forge review` | `forge assign {soul}: 리뷰 피드백 반영` — 수정 (fail 시) / `forge sync` — 지식 승격 / `forge rank {soul}` — 랭크 확인 |
| `forge sync` | `forge status` — 전체 현황 / `forge build: {작업}` — 다음 작업 |
| `forge status` | `forge build: {작업}` — 빌드 시작 / `forge review` — 리뷰 / `forge dashboard --cost` — 비용 |
| `forge rank` | `forge build: {작업}` — 경험치 쌓기 / `forge review {soul}` — 리뷰로 승급 촉진 |
| `forge souls` | `forge build: {작업}` — 빌드 시작 / `forge soul-create` — 새 SOUL 추가 |
| `forge soul-create` | `forge-init` — 팀 구성에 추가 / `forge assign {soul}: {작업}` — 바로 작업 배정 |
| `forge dashboard` | `forge build: {작업}` — 다음 작업 / `forge sync` — 지식 정리 |
| `forge dashboard --cost` | `forge budget status` — 예산 상세 / `forge build: {작업}` — 다음 작업 |
| `forge pack install` | `forge-init` — 팀 초기화 / `forge status` — 설치 확인 |
| `forge mailbox` | `forge build: {작업}` — 작업 진행 / `forge status` — 현황 확인 |
| `forge session` | `forge build: {작업}` — 작업 재개 / `forge status` — 현황 |
| `forge recover-history` | `forge assign {soul}: {작업}` — 재시도 / `forge status` — 현황 |
| `forge worktree` | `forge build: {작업}` — 빌드 / `forge worktree status` — 현황 |
| `forge doctor` | `forge status` — 팀 현황 / `forge build: {작업}` — 작업 시작 |
| `forge verify` | `forge assign {soul}: 검증 실패 수정` — 수정 (FAIL 시) / `forge review {soul}` — 크로스 리뷰 |
| `forge explore` | `forge assign {soul}: {작업}` — 컨텍스트 기반 작업 배정 / `forge build: {작업}` — 팀 빌드 |
| `forge insights` | `forge rank {soul}` — 랭크 확인 / `forge dashboard --cost` — 비용 상세 |
| `forge soul` (인터뷰 생성) | `forge assign {soul}: {작업}` — 바로 작업 배정 / `forge-init` — 팀 재구성 |
| `forge soul-create` (스크립트 생성) | `forge-init` — 팀 구성에 추가 / `forge status` — 현황 확인 |

### 안내 출력 형식

결과 보고 마지막에 다음 형식으로 표시:

```
---
💡 다음 작업:
  • `forge review ryn` — 코드 리뷰
  • `forge dashboard --cost` — 비용 확인
  • `forge status` — 전체 현황
```

- 항목은 2~3개 추천 (상황에 맞는 것 우선)
- 현재 상태에 따라 가장 유용한 순서로 정렬
- forge build 완료 후 리뷰 대상이 있으면 리뷰를 첫 번째로
- 에러/실패 시 recover나 재시도를 첫 번째로
