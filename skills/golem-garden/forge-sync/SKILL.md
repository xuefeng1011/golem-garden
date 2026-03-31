---
name: forge-sync
description: 지식 승격 시스템. 프로젝트 학습을 Sage(심사관)가 검증 후 글로벌에 반영.
trigger: forge sync, forge 동기화, 지식 승격, knowledge sync
---

# forge-sync — 지식 승격 시스템

프로젝트에서 배운 지식을 Sage(심사관)가 검증하고 글로벌 SOUL에 반영한다.

## 자동 흐름 (forge build/review 완료 후)

```
작업 완료 시 Claude가 자동으로:
1. 작업 중 발견한 유의미한 학습을 식별
2. knowledge_record 호출하여 기록
   - scope: universal(보편) / project(전용) 자동 분류
   - confidence: high/medium/low 자동 판정
3. scope=universal + confidence=high 이면 승격 대기열에 추가
```

## 수동 트리거

```
forge sync                  ← 승격 대기열 심사 실행
forge sync status           ← 현황 대시보드
forge sync pending          ← 대기열 조회
forge sync history          ← 심사 히스토리
```

## 실행 절차

### Step 1: 대기열 확인

```bash
bash forge.sh sync pending
```

대기열이 비어있으면 종료.

### Step 2: Sage(심사관) 실행

대기열의 각 항목에 대해 Sage SOUL을 Agent로 실행:

```
Agent(
  subagent_type = "oh-my-claudecode:code-reviewer",
  model = "opus",
  prompt = "[GolemGarden Knowledge Audit — Sage]

  심사 대상:
  - SOUL: {soul_name}
  - 학습 내용: {learning}
  - 분류: {scope} / 신뢰도: {confidence}
  - 출처 태스크: {source_task}

  기존 글로벌 전문 지식:
  {글로벌 souls/{name}.md의 전문 지식 섹션 내용}

  심사 체크리스트:
  1. 오염 체크: 특정 프로젝트에서만 유효한가? (포트, 경로, 환경변수, 프로젝트명 포함 여부)
  2. 충돌 체크: 기존 글로벌 지식과 모순되는가?
  3. 품질 체크: 다른 프로젝트에서도 바로 적용 가능한가?
  4. 중복 체크: 이미 글로벌에 비슷한 지식이 있는가?
  5. 구체성 체크: 구체적 기술/수치/패턴이 포함되어 있는가?

  판정:
  - ✅ promote: 5개 모두 통과 → 글로벌 승격
  - ⚠️ hold: 1~2개 불확실 → 보류
  - ❌ reject: 프로젝트 전용 / 추상적 / 충돌 → 기각

  반드시 다음 형식으로 응답:
  VERDICT: {promote|hold|reject}
  REASON: {한 줄 사유}
  ",
  description = "Sage: 지식 승격 심사"
)
```

### Step 3: 판정 적용

Sage의 응답을 파싱하여:

- **promote**:
  ```bash
  bash forge.sh sync-promote {soul_name} "{learning}"
  # → 글로벌 souls/{name}.md 전문 지식에 추가
  # → 심사 히스토리에 기록
  ```

- **hold**:
  ```bash
  bash forge.sh sync-judge {번호} hold "{reason}"
  # → 대기열에 유지, 다음 심사 때 재검토
  ```

- **reject**:
  ```bash
  bash forge.sh sync-judge {번호} reject "{reason}"
  # → 대기열에서 제거, 히스토리에 기각 기록
  ```

### Step 4: 결과 보고

```
"지식 승격 심사 완료:
 ✅ 승격 2건:
   - Ryn: 'JPA @BatchSize(100)이 N+1 해결 최적' → 글로벌 반영
   - Kai: 'React.memo + useMemo 조합 시 리렌더 70% 감소' → 글로벌 반영
 ⚠️ 보류 1건:
   - Ryn: 'P6Spy 드라이버 3.x에서 타임아웃 이슈' → 추가 검증 필요
 ❌ 기각 1건:
   - Bolt: '포트 8443으로 변경' → 프로젝트 전용 설정"
```

## 학습 자동 기록 규칙 (forge-team 완료 시)

forge-team 스킬에서 작업 완료 후, Claude가 다음을 판단하여 자동 기록:

### 기록 대상 (유의미한 학습)
- 버그 해결 시 발견한 패턴/원인
- 성능 개선에 효과적이었던 기법
- 라이브러리/프레임워크의 주의사항
- 에러 핸들링 패턴
- 테스트에서 발견한 엣지케이스

### 기록 제외 (노이즈)
- 단순 CRUD 구현
- 설정 파일 변경
- 타이포 수정
- 프로젝트 전용 환경 설정

### scope 자동 분류 기준

| universal (보편) | project (전용) |
|-----------------|---------------|
| 프레임워크/라이브러리 패턴 | 특정 포트/경로/URL |
| 알고리즘/자료구조 기법 | 프로젝트 전용 설정값 |
| 성능 최적화 수치 | 비즈니스 로직 규칙 |
| 에러 패턴 + 해결법 | 팀 컨벤션 (프로젝트별) |
| DB 쿼리 최적화 | 특정 API 키/시크릿 |

## 에이전트 현황 대시보드

`forge sync status` 실행 시 전체 에이전트 현황을 종합 표시:

```
=== GolemGarden Agent Dashboard ===

┌─ SOUL Status ──────────────────────────────────────────┐
│ Name     Role               Rank    Tasks  Rate  Model │
│ Nex      director           junior  12건  100%  opus   │
│ Ryn      backend-developer  junior  25건   96%  sonnet │
│ Kai      frontend-developer novice   8건  100%  sonnet │
│ Zen      qa-tester          novice  15건   93%  haiku  │
│ Sage     knowledge-auditor  junior   5건  100%  opus   │
└────────────────────────────────────────────────────────┘

┌─ Knowledge Sync ──────────────────────────────────────┐
│ 대기: 3건 | 승격: 12건 | 보류: 2건 | 기각: 5건        │
│                                                        │
│ 최근 승격:                                              │
│  • Ryn: JPA @BatchSize(100) N+1 최적 (2026-04-01)      │
│  • Kai: React.memo 리렌더 70% 감소 (2026-03-31)         │
│                                                        │
│ 대기 중:                                                │
│  • Ryn: MariaDB 10.11 JSON 인덱스 주의 (universal/high) │
│  • Zen: Playwright 네트워크 모킹 패턴 (universal/medium) │
└────────────────────────────────────────────────────────┘

┌─ Growth Trend ────────────────────────────────────────┐
│ Ryn  ████████████████████████░  25/50 → Senior까지 25건│
│ Kai  ████████░░░░░░░░░░░░░░░░   8/10 → Junior까지  2건│
│ Zen  ███████████████░░░░░░░░░  15/50 → Senior까지 35건│
└────────────────────────────────────────────────────────┘
```
