---
name: forge-review
description: GolemGarden 크로스 리뷰. 다른 SOUL의 관점에서 코드를 리뷰한다.
trigger: forge review, forge 리뷰, 포지 리뷰, forge 검토, forge 코드리뷰, 리뷰해줘, 코드 리뷰해줘, 코드리뷰
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

### Step 0.5: 메일박스 통지

리뷰 시작 시 Director에게 알림:
```bash
GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh mailbox send {worker} nex review_request "{worker} 리뷰 시작"
```

활성 세션이 있으면 이벤트 기록:
```bash
GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh session log {worker} review_start "{reviewer}에 의한 리뷰"
```

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

### Step 3: 리뷰 실행 (`forge run`)

리뷰어 SOUL을 엔진 네이티브 `forge run`으로 직접 소환한다 (model/tools는 리뷰어 SOUL frontmatter에서 자동 적용 — OMC `code-reviewer` 매핑 폐기):

```bash
GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh run {reviewer} "{리뷰 프롬프트}

리뷰 대상 파일을 읽고 다음 관점에서 리뷰하라:
1. 버그 및 로직 오류
2. 성능 이슈
3. 보안 취약점
4. 코드 컨벤션 준수
5. 리뷰어 SOUL의 전문 지식 기반 도메인 체크

결과를 다음 형식으로 반환:
- result: pass 또는 fail
- issues_found: 발견된 이슈 수
- severity: none, minor, major, critical
- details: 상세 피드백"
```

- 반환값: 리뷰 산출물(stdout) + 마지막 `<usage> ... result=...` 라인
- **리뷰어의 성장/비용은 `forge run`이 자동 기록**한다 (Step 4에서 별도 `log-add` 금지)

**에러 처리:**
- `forge run {reviewer}` 실패 시: "리뷰 실행 오류. `forge review {worker}`로 재시도하세요" 안내
- 응답에 result/issues_found/severity 형식이 없을 시: 원문 응답을 보여주고 사용자에게 pass/fail 수동 판정 요청
- 리뷰 대상 파일이 없을 시 (git diff 비어있음): "변경 사항 없음. 리뷰 건너뜀" 안내

### Step 4: 리뷰 결과 기록 (판정만 — 비용은 자동)

리뷰 판정 결과를 파싱하여 워커의 리뷰 이력에 기록한다:

```bash
GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh review-record {worker} {reviewer} "{target}" {result} {issues_found} {severity}
```

- `review-record`는 **워커**의 리뷰-통과 이벤트를 기록한다 (랭크 승급 판정용 — 리뷰어 실행 비용과는 별개).

**리뷰어 SOUL의 성장/비용은 Step 3의 `forge run`이 이미 자동 기록**했다.
→ 따라서 **여기서 `log-add` / `log-add-usage`를 다시 호출하지 마라 (중복 기록됨)**. `<usage>` 라인은 표시용으로만 사용한다.

### Step 5: 이슈 수정 (fail인 경우)

리뷰 결과가 `fail`이면:
1. 리뷰 피드백을 사용자에게 보고한다
2. **자동으로 forge assign을 트리거하지 않는다** (재귀 루프 방지)
3. 사용자에게 수정 방안을 제안하고 선택을 기다린다:
   - "리뷰 이슈 {N}건 발견. 수정하시겠습니까? (`forge assign {worker}: 리뷰 피드백 반영`)"
4. 사용자가 수정을 요청하면 그때 forge-assign 실행
5. 재리뷰는 최대 1회, 사용자 명시적 요청 시에만 실행

### Step 5.5: 메일박스 결과 통지

리뷰 완료 후 결과를 메일박스로 전송:
```bash
GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh mailbox send {reviewer} {worker} info "리뷰 완료: {result} ({issues_found}건 이슈)"
GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh mailbox send {reviewer} nex task_done "리뷰 완료: {worker} → {result}"
```

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
3. forge run zen "{리뷰 프롬프트}" 실행 (Zen model/tools 자동, 비용 자동 기록)
4. 결과: pass, 0건 이슈
5. GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh review-record ryn zen "전체 변경사항" pass 0 none
6. GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh rank ryn → "novice 유지 (tasks=5, streak=3)"

응답: "리뷰 완료! Zen이 Ryn의 코드를 리뷰 → Pass (이슈 0건). 무결함 3연속!

---
💡 다음 작업:
  • `forge sync` — 지식 승격 심사
  • `forge rank ryn` — 랭크 확인
  • `forge build: {작업}` — 다음 빌드"
```

## ⚠️ 필수: 연관 작업 안내

**리뷰 결과 보고 마지막에 반드시 연관 작업 안내를 포함한다.**

| 리뷰 결과 | 안내 내용 |
|-----------|----------|
| **pass** | `forge sync` — 지식 승격 / `forge rank {soul}` — 랭크 확인 / `forge build: {작업}` — 다음 작업 |
| **fail** | `forge assign {worker}: 리뷰 피드백 반영` — 수정 / `forge review {worker}` — 재리뷰 |
