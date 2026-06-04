---
name: forge-init
description: GolemGarden 프로젝트 초기화. 엔진 네이티브 심층 분석 후 최적의 SOUL 팀을 구성한다.
trigger: forge-init, forge init, forge 초기화, 포지 init, 포지 초기화, forge 시작, 포지 시작, forge 셋업, forge setup team, forge 팀 구성, forge 팀구성
---

# forge-init — 프로젝트 초기화 실행 스킬

사용자가 `forge-init` 또는 `forge-init: {설명}` 형태로 입력하면 이 스킬이 실행된다.
설명이 없어도 **엔진 네이티브 심층 분석**을 통해 프로젝트를 파악하고 팀을 구성한다.

## 실행 개요 (2-Phase)

```
Phase 1: 심층 분석 (호스트 직접 스캔 + Nex 아키텍처 판단)
  → 기술스택, 아키텍처, 의존성, 코드 컨벤션, 기술 부채 파악
  → analysis_result 생성

Phase 2: SOUL 팀 구성 (forge-init 본체)
  → analysis_result 기반으로 SOUL 선택 + 컨텍스트 커스터마이징
  → .golem/ 디렉토리 세팅 완료
```

---

## Phase 1: 심층 분석

**사용자가 기술스택을 직접 알려준 경우 Phase 1을 건너뛰고 Phase 2로 이동한다.**

> Phase 1은 아직 SOUL 팀이 구성되기 전이므로 `forge run`으로 워커 SOUL을 소환할 수 없다.
> 따라서 **탐색은 호스트(Claude)가 Glob/Grep/Read로 직접 수행**하고, 아키텍처 심화 판단만 Director(Nex)에게 `forge run nex`로 위임한다 (Nex는 forge-init 시점에 항상 존재).

### Step 1-1: 호스트 직접 프로젝트 탐색

호스트가 Glob/Grep/Read로 프로젝트를 직접 스캔한다. 다음을 반드시 포함:

1. 프로젝트 유형 (웹앱, API, 게임, 데이터, 모노레포 등)
2. 언어 및 프레임워크 (정확한 버전 포함 — package.json, pom.xml, requirements.txt 등 확인)
3. 백엔드: 프레임워크, DB, ORM, 인증 방식
4. 프론트엔드: 프레임워크, 상태관리, UI 라이브러리
5. 인프라: Docker, K8s, CI/CD, 클라우드
6. 테스트: 프레임워크, 커버리지, 테스트 전략
7. 패키지 구조 및 아키텍처 패턴 (레이어드, 클린, 헥사고날 등)
8. 코드 컨벤션 (린터, 포매터, 네이밍 규칙)
9. 주요 설정 파일 목록 및 내용 요약
10. 외부 의존성 및 API 연동

매우 철저하게(very thorough) 스캔한다. 결과를 `scan_result`로 정리한다.

### Step 1-2: Nex(Director)로 아키텍처 심화 분석

`scan_result`를 Director(Nex)에게 `forge run`으로 넘겨 아키텍처 심화 판단을 받는다 (Nex의 model=opus가 frontmatter에서 자동 적용됨):

```bash
GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh run nex "아래 프로젝트 스캔 결과를 바탕으로 아키텍처 심화 분석을 수행하라.

{scan_result}

다음을 판단하라:
1. 현재 아키텍처의 강점과 약점
2. 기술 부채 식별 (있으면)
3. 모듈 간 의존성 그래프 (핵심 모듈 위주)
4. 핵심 도메인 및 비즈니스 로직 위치
5. 확장 포인트 (어디를 건드리면 영향 범위가 큰지)
6. 보안 고려사항
7. 성능 병목 가능 지점

결과를 구조화하여 반환하라."
```

- `forge run`이 성장/비용을 자동 기록하므로 별도 `log-add` 불필요
- 마지막 `<usage> ...` 라인은 표시용

### Step 1-3: 분석 결과 통합 (analysis_result)

호스트 스캔(scan_result) + Nex 아키텍처 분석 결과를 통합하여 다음 형식으로 정리한다:

```
=== GolemGarden 프로젝트 분석 결과 ===

프로젝트 유형: {웹앱/API/게임/데이터/모노레포}
언어: {Java 17, TypeScript 5.x 등}

[백엔드]
- 프레임워크: {Spring Boot 3.2.x}
- DB: {MariaDB 10.11}
- ORM: {JPA/Hibernate}
- 인증: {Spring Security + JWT}
- 아키텍처: {레이어드 / 클린 / 헥사고날}

[프론트엔드]
- 프레임워크: {React 18 + Next.js 14}
- 상태관리: {Zustand / Redux}
- UI: {Tailwind CSS}
- 빌드: {Vite / Webpack}

[인프라]
- 컨테이너: {Docker Compose}
- CI/CD: {GitHub Actions}
- 배포: {AWS / Vercel}

[테스트]
- 프레임워크: {JUnit 5, Jest, Cypress}
- 커버리지: {약 N%}

[코드 품질]
- 린터: {ESLint airbnb, ktlint}
- 포매터: {Prettier}
- 컨벤션: {camelCase, 4-space indent 등}

[아키텍처 소견]
- 강점: {...}
- 약점/기술부채: {...}
- 핵심 도메인: {...}
- 확장 위험 지점: {...}
```

### Step 1-4: 사용자 확인

분석 결과를 사용자에게 보여주고 확인받는다:

```
"프로젝트를 분석했습니다:
 - Spring Boot 3.2 + React 18 + MariaDB
 - Docker 배포, GitHub Actions CI/CD
 - 레이어드 아키텍처, JPA 사용
 - 기술부채: N건 감지
 
 이 구성으로 SOUL 팀을 만들까요?"
```

사용자가 수정을 요청하면 반영 후 Phase 2 진행.

**Phase 1 에러 처리:**
- 호스트 스캔이 빈약/실패 시: 기본 파일 스캔(`ls`, `find`)으로 폴백하여 최소 정보 수집
- `forge run nex` 실패 시: 호스트 스캔 결과(scan_result)만으로 Phase 2 진행 (아키텍처 소견 없이)
- 사용자가 분석 결과를 거부 시: 사용자 입력으로 직접 기술스택 지정 → Phase 2 진행

---

## Phase 2: SOUL 팀 구성

### Step 2-1: 팀 구성 결정

Phase 1의 analysis_result를 기반으로 팀을 구성한다.

#### 자동 매칭 규칙

| 분석 결과 | SOUL 배정 |
|----------|----------|
| 백엔드 프레임워크 감지 | Ryn (backend-developer) |
| 프론트엔드 프레임워크 감지 | Kai (frontend-developer) |
| 백엔드 + 프론트엔드 둘 다 | Ryn + Kai + Nex(Director) |
| Docker/K8s/CI 감지 | Bolt (devops-engineer) |
| 테스트 프레임워크 감지 | Zen (qa-tester) |
| 게임 엔진 감지 (Cocos, Unity, Canvas) | gamedev 팩 |
| 데이터 분석 라이브러리 감지 (pandas, numpy) | trading/data 팩 |
| 보안 관련 코드 (auth, crypto) | 보안 SOUL 추가 고려 |

#### 팩 설치 또는 개별 생성

```bash
# 팩 매칭 시
GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh pack install fullstack

# 개별 생성 시
GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh soul-create backend-developer
GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh soul-create frontend-developer
GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh soul-create qa-tester
```

### Step 2-2: SOUL 컨텍스트 커스터마이징 (프로젝트별 오버라이드)

**글로벌 SOUL 원본은 건드리지 않는다.**
대신 `.golem/souls/`에 프로젝트별 오버라이드 파일을 생성한다.

#### 절차:

1. `.golem/souls/` 디렉토리 생성 (없으면):
   ```bash
   mkdir -p .golem/souls
   ```

2. 팀에 배정된 각 SOUL에 대해:
   - 글로벌 원본(`~/.claude/golem-garden/souls/{name}.md`)을 Read로 읽기
   - 원본을 복사하여 `.golem/souls/{name}.md`로 Write
   - **Phase 1에서 분석한 실제 프로젝트 정보**로 `프로젝트 컨텍스트` 섹션을 수정:

```markdown
## 프로젝트 컨텍스트 (프롬프트에 주입됨)
- 역할: {SOUL role}
- 기술스택: {Phase 1 실제 스캔 결과 — Spring Boot 3.2, MariaDB 10.11 등}
- 아키텍처: {Phase 1 실제 패키지 구조 분석 — 레이어드, 클린 등}
- 코드 컨벤션: {Phase 1 실제 린터/포매터 설정}
- 우선순위: {아키텍처 소견 기반 판단}
- 핵심 도메인: {Phase 1 핵심 비즈니스 로직 위치}
- 주의사항: {Phase 1 기술부채/확장 위험 지점}
```

**중요:**
- 글로벌 원본은 절대 수정하지 않음 → 다른 프로젝트에 영향 없음
- `.golem/souls/`에 있는 파일이 글로벌보다 우선 적용됨
- 프리셋 기본값이 아닌 **Phase 1 실제 분석 결과**를 반영
  예) 프리셋은 "Spring Boot 3.x"이지만, pom.xml이 2.7이면 "Spring Boot 2.7"로 반영

3. **전문 지식 섹션도 프로젝트에 맞게 보강**:
   - Phase 1에서 감지된 구체적 기술 스택을 전문 지식에 추가
   - 예: Ryn의 전문 지식에 "Spring WebFlux reactive 스트림 처리" 추가 (WebFlux 감지 시)
   - 예: Kai의 전문 지식에 "Zustand 상태관리 패턴" 추가 (Zustand 감지 시)

4. `.golem/growth-log/` 초기화:
   ```bash
   mkdir -p .golem/growth-log
   ```
   각 SOUL에 대해 초기 로그 생성:
   ```bash
   GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh log-add {name} "forge-init" success 0 0
   ```

### Step 2-3: .golem/forge-board.md 생성

`.golem/forge-board.md`를 생성한다.
`~/.claude/golem-garden/templates/forge-board.md`를 Read로 읽고, Phase 1 분석 결과 + 팀 구성으로 채워서 Write한다.

forge-board.md에 반영할 Phase 1 정보:
- 프로젝트명, 기술스택 (실제 버전)
- 각 SOUL의 역할 + model/tools (SOUL frontmatter 기준 — `forge run`이 소비)
- 아키텍처 소견에서 도출된 우선순위

### Step 2-4: .golem/analysis.md 저장 (분석 결과 영구 보존)

Phase 1의 전체 분석 결과를 `.golem/analysis.md`로 저장한다.
이 파일은 이후 `forge build` 시 추가 컨텍스트로 참조 가능하다.

```markdown
---
analyzed: {날짜}
analyzer: host scan + forge run nex
---

{Phase 1 Step 1-3의 전체 analysis_result}
```

### Step 2-5: 결과 보고

`GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh status` 실행하여 최종 팀 구성을 사용자에게 보여준다.

보고 내용:
- 분석 기반 팀 구성 결과
- 각 SOUL의 프로젝트 맞춤 컨텍스트 요약
- `.golem/` 디렉토리 구조
- 다음 단계 안내: `forge build: {작업}` 으로 팀 빌드 시작

## ⚠️ 필수: 연관 작업 안내

**init 완료 보고 마지막에 반드시 연관 작업 안내를 포함한다:**
- `forge build: {작업}` — 팀 빌드 시작
- `forge status` — 팀 현황 확인
- `forge dashboard --cost` — 비용 대시보드

---

## 예시 실행 흐름

### 예시 A: 설명 없이 forge-init만 입력

```
사용자: forge-init

AI 실행:
[Phase 1 — 심층 분석]
1. 호스트 직접 스캔(Glob/Grep/Read): 프로젝트 파일 구조, 설정 파일, 소스 코드 전체 탐색
   → "Spring Boot 3.2, React 18, MariaDB, Docker, GitHub Actions"
2. forge run nex "{scan_result} 아키텍처 분석": (Nex model=opus 자동)
   → "레이어드 아키텍처, JPA N+1 위험 3건, 인증 미구현"

3. 사용자에게 분석 결과 보고 + 확인 요청

[Phase 2 — SOUL 팀 구성]  
4. fullstack 팩 설치 (Nex, Ryn, Kai, Zen, Bolt)
5. 글로벌 souls/ 복사 → .golem/souls/에 오버라이드 생성
   - ryn.md: 기술스택 "Spring Boot 3.2, MariaDB 10.11, JPA"
   - kai.md: 기술스택 "React 18, TypeScript 5.3, Tailwind"
   - ryn.md 전문지식에 "JPA N+1 위험 3건 감지됨 — BatchSize 전략 우선 적용" 추가
6. .golem/forge-board.md 생성
7. .golem/analysis.md 저장
8. forge status 출력

응답: "분석 완료 & 팀 구성!
 - Nex(Director), Ryn(Backend), Kai(Frontend), Zen(QA), Bolt(DevOps)
 - 기술부채: JPA N+1 위험 3건 → Ryn 컨텍스트에 반영
 - `forge build: 작업내용` 으로 시작하세요

---
💡 다음 작업:
  • `forge build: {작업}` — 팀 빌드 시작
  • `forge status` — 팀 현황 확인"
```

### 예시 B: 기술스택을 직접 알려준 경우

```
사용자: forge-init: Django + React + PostgreSQL

AI 실행:
[Phase 1 건너뜀 — 사용자가 이미 알려줌]

[Phase 2]
1. soul-create backend-developer → Ryn
2. .golem/souls/ryn.md: "Django 4.x, PostgreSQL" 반영
3. soul-create frontend-developer → Kai
4. .golem/souls/kai.md: "React, TypeScript" 반영
5. soul-create qa-tester → Zen
6. .golem/forge-board.md 생성
7. forge status 출력
```

### 예시 C: 신규 빈 프로젝트

```
사용자: forge-init

AI 실행:
[Phase 1]
1. 호스트 직접 스캔: 파일 거의 없음 → 빈 프로젝트 판단

2. 사용자에게 질문:
   "새 프로젝트인 것 같습니다.
    어떤 유형을 만드시나요?
    1) 풀스택 웹앱 (Spring Boot + React)
    2) API 서버 (Spring Boot only)
    3) 프론트엔드 (React/Next.js)
    4) 게임 (Cocos Creator)
    5) 데이터 분석/트레이딩
    6) 직접 입력"

3. (사용자 응답 후 Phase 2 진행)
```

---

## forge.sh 호출 규칙 (중요)

**모든 `bash ~/.claude/golem-garden/forge.sh` 호출 시 반드시 `GOLEM_PROJECT`를 현재 작업 디렉토리로 설정하라:**

```bash
GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh {command} {args}
```

이렇게 하면:
- `.golem/souls/` 프로젝트 오버라이드가 적용됨
- `.golem/growth-log/` 프로젝트별 성장 기록에 저장됨
- `.golem/forge-board.md` 팀 구성이 읽힘

**절대 `GOLEM_PROJECT` 없이 호출하지 마라.** 글로벌에만 기록되고 프로젝트에 반영 안 됨.
