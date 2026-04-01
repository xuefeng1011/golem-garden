---
name: forge-soul
description: 전문가 수준 SOUL 생성기. 대화형 문진으로 용도를 파악하고 최적의 에이전트를 설계한다.
trigger: forge soul, forge-soul, 소울 만들어, 에이전트 만들어, 새 에이전트, SOUL 생성
---

# forge-soul — 전문가 수준 SOUL 생성기

사용자가 새 에이전트를 원할 때, 다각도 문진을 통해 전문가 수준의 SOUL을 설계하고 생성한다.

## 트리거 인식

```
forge soul                          ← 문진 시작
forge-soul: DevOps 엔지니어           ← 역할 힌트 포함
새 에이전트 만들어줘                    ← 자연어
SOUL 생성: 데이터 파이프라인 전문가      ← 역할 직접 지정
에이전트 추가해줘                      ← 자연어
```

## 실행 절차

### Phase 1: 문진 (인터뷰)

사용자에게 단계적으로 질문한다.
**한번에 모든 질문을 던지지 않는다.** 답변에 따라 다음 질문이 달라진다.

#### Q1: 용도 파악 (필수)

```
"어떤 작업을 위한 에이전트가 필요하세요?
 예시: 'CI/CD 파이프라인 구축', 'DB 성능 최적화', '디자인 시스템 구축'"
```

사용자가 이미 트리거에 힌트를 줬으면 (`forge-soul: DevOps`) 확인만 하고 넘어간다:
```
"DevOps 엔지니어를 만들까요? 좀 더 구체적인 용도가 있으면 알려주세요."
```

#### Q2: 도메인 심화 (답변 기반)

Q1 답변을 분석하여 도메인별 심화 질문:

| Q1 답변 키워드 | 심화 질문 |
|--------------|----------|
| CI/CD, 배포, 인프라 | "주 사용 플랫폼은? (AWS/GCP/Azure/온프레미스) 컨테이너 사용? (Docker/K8s)" |
| DB, 쿼리, 성능 | "어떤 DB? (RDB/NoSQL/둘다) 주요 이슈는? (느린 쿼리/마이그레이션/설계)" |
| 프론트엔드, UI | "프레임워크는? (React/Vue/Svelte) 관심사는? (성능/접근성/애니메이션)" |
| 데이터, 분석 | "어떤 분석? (통계/ML/시각화) 데이터 규모는? (소규모/빅데이터)" |
| 보안, 인증 | "영역은? (웹보안/인프라보안/암호화) 컴플라이언스? (GDPR/HIPAA/없음)" |
| 테스트, QA | "테스트 종류? (단위/E2E/성능) 자동화 수준은?" |
| 문서, 기술문서 | "대상 독자는? (개발자/비개발자/API사용자) 형식은? (API문서/가이드/다이어그램)" |

#### Q3: 작업 스타일 (선택)

```
"이 에이전트의 작업 스타일을 골라주세요 (또는 직접 입력):

 1) 신중하고 안전 우선 — 변경 전 반드시 검증, 롤백 계획 수립
 2) 빠르고 과감한 실행 — 프로토타입 우선, 반복 개선
 3) 자동화 중독 — 수작업 발견 즉시 자동화, 반복 혐오
 4) 완벽주의자 — 코드 품질 최우선, 리팩토링 적극적
 5) 실용주의자 — 동작하는 코드 우선, 과도한 추상화 회피
 6) 직접 입력

 또는 '알아서' 라고 하면 용도에 맞게 자동 배정합니다."
```

#### Q4: 이름과 성별 (선택)

```
"이름을 지어주세요. 또는 '알아서'라고 하면 자동으로 정합니다.
 추천: {용도 기반 3개 이름 제안}"
```

이름 자동 생성 규칙:
- 2~3음절 영문 이름
- 역할의 느낌을 반영 (보안→강한 이름, 데이터→과학적 이름)
- 기존 SOUL과 겹치지 않는 이름
- 성별은 이름에서 자연스럽게 암시 (프롬프트에 주입하지 않음)

**사용자가 직접 이름/성별을 지정하면 그대로 따른다.**

### Phase 2: SOUL 설계 (AI가 자동)

문진 결과를 종합하여 전문가 수준으로 SOUL을 설계한다.

#### 2-1. role 결정

문진 내용에서 가장 적합한 OMC 에이전트 role 매핑:

| 용도 | role | OMC Agent |
|------|------|-----------|
| 백엔드/API/DB | backend-developer | executor |
| 프론트엔드/UI/UX | frontend-developer | designer |
| DevOps/CI/CD/인프라 | devops-engineer | executor |
| 테스트/QA | qa-tester | test-engineer |
| 데이터/분석/ML | data-analyst | scientist |
| 보안/감사 | security-auditor | security-reviewer |
| 문서/기술문서 | technical-writer | writer |
| 아키텍처/설계 | architect | architect |
| 게임로직 | game-logic-developer | executor |
| 기획/디자인 | game-designer | planner |

매칭되는 role이 없으면 커스텀 role을 만든다.

#### 2-2. specialty 생성 (5~8개)

문진에서 파악한 기술스택 + 도메인 전문성을 태그로 변환.
**구체적이고 검색 가능한 키워드**로 만든다:

```
나쁜 예: [backend, coding, development]          ← 너무 범용
좋은 예: [spring-boot, jpa, query-optimization, flyway, clean-architecture]  ← 구체적
```

#### 2-3. 전문 지식 생성 (4~6개)

해당 분야의 **실무에서 자주 마주치는 구체적 문제와 해결 패턴**을 작성:

```
나쁜 예: - 데이터베이스를 잘 다룸                    ← 추상적
좋은 예: - JPA N+1 문제 해결 (fetch join, @EntityGraph, batch size)  ← 구체적
```

#### 2-4. 행동 원칙 생성 (2~4개)

문진의 작업 스타일 + 도메인 특성을 반영한 **실행 가능한 원칙**:

```
나쁜 예: - 좋은 코드를 작성한다                     ← 측정 불가
좋은 예: - 인프라 변경은 반드시 IaC로만, 수동 변경 금지   ← 명확한 규칙
```

#### 2-5. 모델 결정

| 역할 특성 | 모델 | 이유 |
|----------|------|------|
| 아키텍처, 보안, 복잡한 판단 | opus | 깊은 추론 필요 |
| 일반 개발, 디자인, 분석 | sonnet | 코딩 최적 |
| 단순 작업, 문서, 반복 업무 | haiku | 비용 효율 |

#### 2-6. personality 생성

성격은 **프롬프트에 주입되지 않는 사용자 메모용**이지만,
SOUL의 캐릭터성을 부여하여 팀원처럼 느끼게 한다.

문진 결과 기반으로 자동 생성:
- 작업 스타일에서 성격 파생
- 도메인 특성 반영한 말투/태도
- 한 줄로 간결하게

예시:
- DevOps + 자동화 중독 → "자동화 중독. 수작업은 죄악이다."
- DB 전문가 + 신중 → "쿼리 하나에 목숨 건다. EXPLAIN 없이 실행하면 잠 못 잔다."
- 보안 + 완벽주의 → "편집증적 보안 감각. 모든 입력은 공격이라고 가정한다."

### Phase 3: 생성 및 확인

#### 3-1. SOUL 파일 생성

1. 글로벌에 생성:
   ```
   Write: ~/.claude/golem-garden/souls/{name}.md
   ```

2. 현재 프로젝트에 `.golem/`이 있으면 오버라이드도 생성:
   ```
   Write: .golem/souls/{name}.md
   → 프로젝트 기술스택에 맞게 프로젝트 컨텍스트 수정
   ```

3. growth-log 초기화:
   ```bash
   GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh log-add {name} "forge-soul-create" success 0 0
   ```

#### 3-2. 생성 결과 리뷰

생성된 SOUL을 사용자에게 보여주고 확인:

```
"새 SOUL을 만들었습니다:

 ┌───────────────────────────────────┐
 │ ⚡ Cira (devops-engineer)         │
 │ Rank: Novice | Model: sonnet     │
 │                                   │
 │ Specialty:                        │
 │  docker, kubernetes, terraform,   │
 │  github-actions, monitoring,      │
 │  aws-ecs, datadog                 │
 │                                   │
 │ 성격: 자동화 중독. 수작업은 죄악.    │
 │                                   │
 │ 행동 원칙:                         │
 │  • 인프라 변경은 반드시 IaC로만     │
 │  • 모니터링 없는 배포는 배포가 아님  │
 │  • CI 파이프라인 5분 초과 시 최적화  │
 └───────────────────────────────────┘

 수정할 부분이 있으면 말씀하세요. 없으면 이대로 확정합니다."
```

사용자가 수정 요청하면 해당 부분만 Edit으로 수정.

#### 3-3. forge-board 업데이트

`.golem/forge-board.md`가 있으면 새 SOUL을 팀 구성 테이블에 추가.

## 예시 실행 흐름

### 예시 A: 최소 입력

```
사용자: 새 에이전트 만들어줘

AI: "어떤 작업을 위한 에이전트가 필요하세요?"
사용자: CI/CD 파이프라인 관리

AI: "주 사용 플랫폼은? (AWS/GCP/Azure/온프레미스) 컨테이너 사용하세요?"
사용자: AWS, Docker + ECS

AI: "작업 스타일을 골라주세요:
     1) 신중하고 안전 우선
     2) 빠르고 과감한 실행
     3) 자동화 중독
     4) 직접 입력
     또는 '알아서'"
사용자: 3

AI: "이름을 지어주세요. 추천: Cira, Atlas, Forge"
사용자: Cira

AI: (SOUL 생성 후 카드 표시)
    "Cira(devops-engineer) 생성 완료! 수정할 부분 있으면 말씀하세요."
사용자: 좋아

AI: "확정! forge build에서 Cira를 사용할 수 있습니다."
```

### 예시 B: 구체적 입력

```
사용자: forge-soul: MariaDB 성능 튜닝 전문가, 이름은 Astra, 신중한 성격으로

AI: "MariaDB 성능 튜닝 전문 SOUL, 이름 Astra, 신중한 스타일로 만들겠습니다.
     추가로 확인:
     - 주요 이슈는? (느린 쿼리 / 인덱스 / 리플리케이션 / 파티셔닝)"
사용자: 느린 쿼리 + 인덱스 최적화가 메인

AI: (SOUL 생성 — 심화 문진 1개만 하고 바로 생성)
    "Astra(backend-developer) 생성 완료!
     specialty: [mariadb, query-optimization, index-strategy, explain-analyze, slow-query-log]
     성격: 쿼리 하나에 목숨 건다. EXPLAIN 없이 실행하면 잠 못 잔다."
```

### 예시 C: 완전 자동

```
사용자: forge-soul: API 문서화 담당자 알아서 만들어줘

AI: (문진 생략, 전부 자동)
    "Echo(technical-writer) 생성 완료!
     specialty: [openapi, swagger, jsdoc, markdown, diagram, api-documentation]
     성격: 명확한 문서를 쓴다. 독자가 5분 안에 이해 못하면 실패."
```
