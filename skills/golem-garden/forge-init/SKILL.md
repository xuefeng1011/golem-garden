---
name: forge-init
description: GolemGarden 프로젝트 초기화. 팀 구성과 SOUL 파일 생성.
trigger: forge-init
---

# forge-init — 프로젝트 초기화

프로젝트 유형을 파악하고 최적의 SOUL 팀을 구성한다.

## 워크플로우

### Step 1: 프로젝트 분석

사용자 입력에서 프로젝트 정보를 추출한다:
- 프로젝트 유형 (웹앱, API, 풀스택, 게임, 데이터 분석 등)
- 기술스택 (언어, 프레임워크, DB 등)
- 팀 규모 요구사항

### Step 2: SOUL 팀 추천

프로젝트 유형에 따라 SOUL 조합을 추천한다:

| 프로젝트 유형 | 추천 SOUL 구성 |
|-------------|--------------|
| Backend API | Nex(Director) + Ryn(Backend) + Zen(QA) |
| Frontend SPA | Nex(Director) + Kai(Frontend) + Zen(QA) |
| 풀스택 웹앱 | Nex + Ryn + Kai + Zen |
| 풀스택 + 배포 | Nex + Ryn + Kai + Zen + Bolt(DevOps) |
| 게임 개발 | Nex + Sprite + Pixel + Glitch |
| 데이터 분석 | Nex + Nova(Analyst) + Zen(QA) |

### Step 3: SOUL 파일 생성

1. `souls/` 디렉토리에서 기존 SOUL 확인
2. 필요한 SOUL이 없으면 `templates/soul-template.md` 기반으로 생성
3. 프로젝트 컨텍스트를 SOUL.md에 반영:
   - 기술스택 정보 주입
   - 아키텍처 패턴 주입
   - 코드 컨벤션 주입

### Step 4: forge-board.md 생성

`templates/forge-board.md` 템플릿을 기반으로 프로젝트 루트에 `forge-board.md` 생성:
- 팀 구성 테이블 작성
- 기술스택 기록
- OMC 실행 모드 기본값 설정

### Step 5: growth-log 초기화

각 SOUL에 대해 `growth-log/{name}.jsonl` 파일 생성:
```json
{"date":"{{DATE}}","task":"forge-init","result":"success","files_changed":0,"tests_passed":0}
```

## 실행 예시

```
사용자: forge-init: 풀스택 웹앱, Spring Boot + React

실행 결과:
1. souls/nex.md  — Director (기존 로드)
2. souls/ryn.md  — Backend Developer (기존 로드, Spring Boot 컨텍스트 업데이트)
3. souls/kai.md  — Frontend Developer (신규 생성, React 컨텍스트)
4. souls/zen.md  — QA/Tester (신규 생성)
5. forge-board.md — 팀 구성 완료
6. growth-log/   — 각 SOUL 초기 로그 생성
```

## 프롬프트 주입 형식

forge-init 완료 후, 각 SOUL이 OMC 에이전트에 주입될 때의 형식:

```
[GolemGarden Context — {SOUL_NAME} ({ROLE})]
프로젝트 컨텍스트:
- 기술스택: {TECH_STACK}
- 아키텍처: {ARCHITECTURE}
- 코드 컨벤션: {CONVENTIONS}
- 우선순위: {PRIORITIES}

전문 지식 힌트:
- {EXPERTISE_ITEMS}

이전 작업 이력: {TASK_COUNT}건, 성공률 {SUCCESS_RATE}%
현재 랭크: {RANK}

이 컨텍스트에서 다음 태스크를 수행하라:
{TASK_DESCRIPTION}
```
