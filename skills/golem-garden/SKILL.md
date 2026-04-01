---
name: golem-garden
description: GolemGarden 메인 라우터. "forge"로 시작하는 모든 명령을 처리한다.
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

## 라우팅 판단 로직

사용자 입력을 받으면 다음 순서로 판단한다:

### 1. 키워드 매칭

| 우선순위 | 키워드 | 동작 |
|---------|--------|------|
| 1 | `init`, `초기화`, `셋업`, `setup`, `시작`, `팀 구성` | → forge-init 스킬 직접 실행 (forge.sh init을 호출하지 않음. 스킬이 직접 프로젝트를 스캔한다) |
| 2 | `build`, `빌드`, `만들어`, `구현`, `개발` | → forge-team (ultrapilot) |
| 3 | `quick`, `퀵`, `간단`, `빠르게` | → forge-team (autopilot) |
| 4 | `assign` 또는 SOUL이름 + 태스크 | → forge-team (수동) |
| 5 | `review`, `리뷰`, `검토`, `코드리뷰` | → forge-review |
| 6 | `status`, `상태`, `현황`, `목록` | → forge status |
| 7 | `rank`, `랭크`, `레벨`, `승급` | → forge rank |
| 8 | `soul`, `소울`, `에이전트`, `추가`, `만들어` + 역할 | → forge-soul 스킬 실행 (대화형 문진 생성기) |
| 9 | `pack`, `팩` | → forge pack |

### 2. SOUL 이름 감지

입력에 등록된 SOUL 이름이 있고 + 태스크 설명이 있으면:
→ `forge assign {soul}: {태스크}`로 처리

### 3. 애매한 경우

위 규칙으로 판단이 안 되면 사용자에게 되물어본다:
```
"어떤 작업을 원하시나요?
1) 팀 구성 (forge-init)
2) 코드 생성 (forge build)
3) 리뷰 (forge review)
4) 상태 확인 (forge status)"
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
