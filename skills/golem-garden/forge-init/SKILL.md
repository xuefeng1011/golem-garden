---
name: forge-init
description: GolemGarden 프로젝트 초기화. 프로젝트 구조를 자동 분석하고 최적의 SOUL 팀을 구성한다.
trigger: forge-init, forge init
---

# forge-init — 프로젝트 초기화 실행 스킬

사용자가 `forge-init` 또는 `forge-init: {설명}` 형태로 입력하면 이 스킬이 실행된다.
설명이 없어도 **프로젝트를 자동 분석**하여 팀을 구성한다.

## 실행 절차

### Step 0: 프로젝트 자동 스캔 (가장 먼저)

사용자 입력에 기술스택 정보가 없거나 부족하면, 먼저 프로젝트를 분석한다.
**반드시 아래 순서대로 실행:**

#### 0-1. 디렉토리 구조 스캔

```
Bash: ls -la (프로젝트 루트)
Bash: find . -maxdepth 2 -type f -name "*.json" -o -name "*.xml" -o -name "*.gradle" -o -name "*.yml" -o -name "*.yaml" -o -name "Makefile" -o -name "Dockerfile" -o -name "*.toml" -o -name "*.cfg" -o -name "requirements*.txt" | head -30
```

#### 0-2. 핵심 설정 파일 읽기 (존재하는 것만)

| 파일 | 확인 내용 |
|------|----------|
| `package.json` | Node.js 프로젝트, 프레임워크(react, vue, next, express 등), 의존성 |
| `pom.xml` | Java/Spring 프로젝트, Spring Boot 버전, 의존성 |
| `build.gradle` / `build.gradle.kts` | Gradle 프로젝트, 의존성 |
| `requirements.txt` / `pyproject.toml` / `Pipfile` | Python 프로젝트, 프레임워크(django, flask, fastapi 등) |
| `go.mod` | Go 프로젝트, 모듈 |
| `Cargo.toml` | Rust 프로젝트 |
| `docker-compose.yml` / `Dockerfile` | 컨테이너 구성, DB 종류 |
| `.github/workflows/*.yml` | CI/CD 파이프라인 |
| `tsconfig.json` | TypeScript 설정 |
| `.env.example` / `.env.sample` | 환경 변수 힌트 (DB, API 키 등) |

**Read tool로 존재하는 파일을 병렬로 읽는다.**

#### 0-3. 소스 구조 파악

```
Bash: find . -maxdepth 3 -type d | grep -v node_modules | grep -v .git | grep -v __pycache__ | grep -v target | grep -v build | grep -v dist | head -40
```

#### 0-4. 분석 결과 정리

스캔 결과를 종합하여 다음을 판단한다:

```
분석 결과:
- 프로젝트 유형: {풀스택 / 백엔드 API / 프론트엔드 / 게임 / 데이터 분석 / 모노레포}
- 언어: {Java, TypeScript, Python, Go 등}
- 백엔드: {Spring Boot 3.x, Express, Django, FastAPI, 없음 등}
- 프론트엔드: {React, Vue, Next.js, 없음 등}
- DB: {MariaDB, PostgreSQL, MongoDB, 없음 등}
- 인프라: {Docker, K8s, GitHub Actions, 없음 등}
- 테스트: {JUnit, Jest, pytest, 없음 등}
- 패키지 구조: {com.example.app, src/components 등}
- 코드 컨벤션 힌트: {ESLint, Prettier, ktlint 등}
```

이 분석 결과를 사용자에게 **먼저 보여주고 확인**받는다:
```
"프로젝트를 분석했습니다:
 - Spring Boot 3.2 + Vue 3 + MariaDB
 - Docker 배포, GitHub Actions CI/CD
 이 구성으로 팀을 만들까요?"
```

### Step 1: 팀 구성 결정

사용자 확인 후 (또는 사용자가 처음부터 기술스택을 명시한 경우) 팀을 구성한다.

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
| 보안 관련 코드 (auth, crypto) | Vex (security-auditor) 추가 고려 |

#### 팩 설치 또는 개별 생성

```bash
# 팩 매칭 시
bash forge.sh pack install fullstack

# 개별 생성 시
bash forge.sh soul-create backend-developer
bash forge.sh soul-create frontend-developer
bash forge.sh soul-create qa-tester
```

### Step 2: SOUL 컨텍스트 커스터마이징

생성된 각 SOUL 파일(`souls/{name}.md`)을 Read로 읽고,
**Step 0에서 분석한 실제 프로젝트 정보**로 Edit하여 업데이트한다:

```markdown
## 프로젝트 컨텍스트 (프롬프트에 주입됨)
- 기술스택: {실제 스캔 결과 — Spring Boot 3.2, MariaDB 10.11 등}
- 아키텍처: {실제 패키지 구조 분석 — 레이어드, 클린, 헥사고날 등}
- 코드 컨벤션: {실제 린터/포매터 설정 — ESLint airbnb, ktlint 등}
- 우선순위: {프로젝트 상태 기반 판단}
```

**중요: 프리셋 기본값이 아닌 실제 분석 결과를 반영한다.**
예) 프리셋은 "Spring Boot 3.x"이지만, 실제 pom.xml이 2.7이면 "Spring Boot 2.7"로 반영.

### Step 3: forge-board.md 생성

프로젝트 루트에 `forge-board.md`를 생성한다.
`templates/forge-board.md`를 Read로 읽고, 분석 결과 + 팀 구성으로 채워서 Write한다.

### Step 4: 결과 보고

`bash forge.sh status` 실행하여 최종 팀 구성을 사용자에게 보여준다.

## 예시 실행 흐름

### 예시 A: 설명 없이 forge-init만 입력

```
사용자: forge-init

AI 실행:
1. [스캔] ls, find로 디렉토리 구조 파악
2. [스캔] package.json 발견 → Read → React 18, TypeScript
3. [스캔] /server/pom.xml 발견 → Read → Spring Boot 3.2, MariaDB
4. [스캔] docker-compose.yml 발견 → Read → MariaDB, Redis
5. [스캔] .github/workflows/ 발견 → CI/CD 있음

6. [보고] "분석 결과:
    - 풀스택: Spring Boot 3.2 + React 18 + MariaDB
    - Docker + GitHub Actions CI/CD
    이 구성으로 팀을 만들까요?"

7. (사용자 확인 후)
8. bash forge.sh pack install fullstack
9. souls/ryn.md Edit → "Spring Boot 3.2, MariaDB" 반영
10. souls/kai.md Edit → "React 18, TypeScript" 반영
11. forge-board.md Write
12. bash forge.sh status → 결과 출력
```

### 예시 B: 기술스택을 직접 알려준 경우

```
사용자: forge-init: Django + React + PostgreSQL

AI 실행:
1. [스캔 생략 — 사용자가 이미 알려줌]
2. bash forge.sh soul-create backend-developer  → Ryn
3. souls/ryn.md Edit → "Django 4.x, PostgreSQL" 반영 (Spring 대신)
4. bash forge.sh soul-create frontend-developer → Kai
5. souls/kai.md Edit → "React, TypeScript" 반영
6. bash forge.sh soul-create qa-tester → Zen
7. forge-board.md Write
8. bash forge.sh status
```

### 예시 C: 신규 빈 프로젝트

```
사용자: forge-init

AI 실행:
1. [스캔] 파일 거의 없음 → 빈 프로젝트로 판단
2. [질문] "새 프로젝트인 것 같습니다.
    어떤 유형의 프로젝트를 만드시나요?
    (풀스택 웹앱 / API 서버 / 프론트엔드 / 게임 / 데이터 분석)"
3. (사용자 응답 후 진행)
```
