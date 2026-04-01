---
name: forge-review
description: GolemGarden 크로스 리뷰. 다른 SOUL의 관점에서 코드를 리뷰한다.
trigger: forge review
---

# forge-review — 크로스 리뷰 실행 스킬

사용자가 `forge review ...` 형태로 입력하거나, forge-team 완료 후 자동 트리거된다.

## 입력 패턴

| 패턴 | 동작 |
|------|------|
| `forge review` | 마지막 작업의 작업자를 자동 감지, 리뷰어 자동 선정 |
| `forge review {worker}` | 지정 작업자, 리뷰어 자동 선정 |
| `forge review {worker} {reviewer}` | 작업자와 리뷰어 모두 지정 |
| `forge review {worker} {reviewer} "{target}"` | 대상까지 지정 |

## 실행 절차

### Step 1: 리뷰 대상 파악

1. 작업자(worker) SOUL 결정
2. 리뷰어(reviewer) 결정:
   - 지정되지 않은 경우 `GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh review {worker}` 실행 → 자동 선정
   - QA SOUL 우선, 없으면 Director, 없으면 다른 아무 SOUL
3. 리뷰 대상 결정:
   - 지정된 경우 해당 파일/모듈
   - 미지정 시 `git diff --name-only` 로 최근 변경 파일 목록 확인

### Step 2: 리뷰 프롬프트 생성

`GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh prompt-review {reviewer} {worker} "{target}"` 실행하여 리뷰 프롬프트 생성.

생성되는 프롬프트 구조:
```
[GolemGarden Review — {리뷰어} ({역할})]
리뷰 관점: {전문 분야}
전문 지식 기반 체크포인트: {전문 지식 목록}
작업자: {작업자} ({역할}), Rank: {랭크}
리뷰 대상: {파일 목록}
```

### Step 3: 리뷰 실행

리뷰어 SOUL의 role에 따른 OMC 에이전트로 실행:

```
Agent(
  subagent_type = "oh-my-claudecode:code-reviewer",
  model = "{리뷰어 SOUL의 model}",
  prompt = "{리뷰 프롬프트}\n\n리뷰 대상 파일을 읽고 다음 관점에서 리뷰하라:
    1. 버그 및 로직 오류
    2. 성능 이슈
    3. 보안 취약점
    4. 코드 컨벤션 준수
    5. 리뷰어 SOUL의 전문 지식 기반 도메인 체크

    결과를 다음 형식으로 반환:
    - result: pass 또는 fail
    - issues_found: 발견된 이슈 수
    - severity: none, minor, major, critical
    - details: 상세 피드백",
  description = "Review: {worker}의 코드를 {reviewer}가 리뷰"
)
```

### Step 4: 리뷰 결과 기록

리뷰 에이전트의 결과를 파싱하여:

```bash
GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh review-record {worker} {reviewer} "{target}" {result} {issues_found} {severity}
```

### Step 5: 이슈 수정 (fail인 경우)

리뷰 결과가 `fail`이면:
1. 리뷰 피드백을 작업자 SOUL에게 전달
2. `forge assign {worker}: "리뷰 피드백 반영: {피드백 내용}"` 형태로 수정 요청
3. 수정 완료 후 재리뷰 (최대 2회)

### Step 6: 랭크 승급 체크

```bash
GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh rank {worker}
```

승급 가능하면:
```bash
GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh promote {worker}
```

### Step 7: 결과 보고

사용자에게 리뷰 결과 요약:
- 리뷰어: {누가}
- 결과: pass/fail
- 발견 이슈: {N}건 ({severity})
- 랭크 변동: {있으면 표시}

## 예시 실행 흐름

```
사용자: forge review ryn

AI 실행:
1. 리뷰어 자동 선정 → Zen (qa-tester)
2. 리뷰 프롬프트 생성 (Zen의 전문 지식 기반)
3. Agent(code-reviewer, haiku, 리뷰 프롬프트) 실행
4. 결과: pass, 0건 이슈
5. GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh review-record ryn zen "전체 변경사항" pass 0 none
6. GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh rank ryn → "novice 유지 (tasks=5, streak=3)"

응답: "리뷰 완료! Zen이 Ryn의 코드를 리뷰 → Pass (이슈 0건). 무결함 3연속!"
```
