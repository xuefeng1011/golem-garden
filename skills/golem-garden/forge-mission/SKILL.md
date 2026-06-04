---
name: forge-mission
description: GolemGarden 단일 목표 완주 모드. 하나의 목적(goal)을 최소 개입으로 완료까지 끌고 간다. 시작 시 일괄 요구사항 인터뷰 → spec 고정 → 자율 실행 → 검증·완료.
trigger: forge mission, 포지 미션, forge 미션, forge mission:, 끝까지 해줘, 완주, 하나의 목적, 하나의 목표 완주
---

# forge-mission — 단일 목표 완주 스킬

사용자가 `forge mission: {목표}` 형태로 입력하면 이 스킬이 실행된다.
이 모드의 본질은 **"하나의 목적을 최소 개입으로 완료까지 끌고 가는 것"** 이다.
일반 `forge build`와의 차이: build는 한 번의 분배·실행·보고로 끝나지만, mission은 **목표가 검증으로 확인될 때까지 execute↔verify 루프를 자율적으로 반복**한다.

## 4대 기둥 (FIXED — 우회 금지)

1. **시작 시 요구사항 인터뷰 = 고정 배치.** 모드 시작 직후 호스트가 질문 UI로 **단 한 번의 배치(3~5개 질문)** 를 던져 목표를 결정화한다. 적응형/최소화가 아니라 항상 같은 카테고리를 묻는다.
2. **자율성: 완주한다.** 아래 3가지 정지 조건 외에는 **절대 사용자에게 중간 확인을 묻지 않는다** ("이렇게 할까요?" 금지). SOUL 실패 시 `forge recover`로 복구하고 계속 진행한다.
3. **완료 = verifier SOUL + 테스트 통과.** 완료는 증거 기반이다. author≠verifier — 작성한 SOUL이 자기 작업을 승인하지 않는다.
4. **자동 스코프: 작으면 단독, 크면 팀.** 목표 크기를 판단해 단독 SOUL 또는 다중 SOUL 팀으로 실행한다.

---

## Phase 1: 요구사항 인터뷰 (고정 배치)

**모드 시작 직후, 호스트의 질문 UI로 단 한 번의 배치 질문을 던진다.** 적응형이 아니다 — 아래 카테고리를 항상 묻는다 (목표에 맞춰 문구만 구체화).

### 고정 질문 템플릿 (3~5개)

```
이 목표를 완주 모드로 진행하기 전에 몇 가지만 확정하겠습니다:

(a) 성공 기준 — 무엇이 "완료"인가요? 구체적이고 테스트 가능한 정의로 알려주세요.
    예: "/login 엔드포인트가 200 반환 + JWT 발급 + 통합테스트 통과"

(b) 제약·기술 — 반드시 써야 할 것 / 절대 쓰면 안 되는 것 / 기술적 제약이 있나요?
    예: "기존 Express 미들웨어 패턴 유지, 외부 인증 SaaS 금지"

(c) 비범위 — 이번 목표에서 명시적으로 제외할 것은 무엇인가요?
    예: "비밀번호 재설정 플로우, 소셜 로그인은 이번엔 제외"

(d) [선택] 우선순위·리스크 허용도 — 속도 vs 완성도, 어디까지 자율 판단해도 되나요?
    예: "정확성 최우선, 파괴적 작업만 사전 확인"
```

- 질문은 **반드시 호스트의 question UI(한 배치)로** 전달한다. 한 개씩 순차로 묻지 않는다.
- 사용자가 이미 목표 문장에 일부 답을 포함했어도, 인터뷰 배치는 생략하지 않는다 (비어있는 항목만 묻거나, 확인 형태로 묻는다).

### Step 1-1: spec 영구화

인터뷰 답변을 받으면 즉시 mission spec으로 영구화한다:

```bash
GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh mission init "{목표}" "{성공 기준}" "{제약·기술}" "{비범위}"
```

- 이 명령은 **mission id를 echo** 하고 `.golem/missions/<id>/spec.md`를 생성한다 (## 목표 / ## 성공 기준 / ## 제약·범위 / ## 비범위 / ## 태스크).
- echo된 `<id>`를 이후 모든 mission 명령에 사용한다. 변수로 잡아둔다.

---

## Phase 2: 스코프 판단 + 태스크 분해

### Step 2-1: 목표 크기 판단 (자동 스코프)

호스트가 spec을 기준으로 목표 크기를 판단한다:

| 크기 | 판단 기준 | 실행 방식 |
|------|----------|----------|
| **작음 (solo)** | 단일 파일/단일 도메인, 자명한 변경 | 최적 SOUL 1개 단독 실행 |
| **큼 (team)** | 다중 파일/다중 시스템, 분해 필요 | Nex 분해 → 다중 SOUL 팀 |

### Step 2-2: 태스크 분해

#### 작음 (solo)
1. 목표에 가장 적합한 단일 SOUL을 선택한다 (role/specialty 매칭).
2. 태스크 1개를 spec에 기록:
   ```bash
   GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh mission set-tasks <id> "{단일 태스크}"
   ```

#### 큼 (team)
1. Director(Nex)에게 분해를 위임한다 (model=opus 자동 적용):
   ```bash
   GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh run nex "다음 목표를 완주하기 위한 서브태스크로 분해하고 각 서브태스크를 가용 SOUL에 배정하라.

   목표: {목표}
   성공 기준: {성공 기준}
   제약: {제약}
   비범위: {비범위}

   가용 SOUL (역할 / 랭크): {soul1} ({role}, {rank}), {soul2} (...)

   다음 형식으로 반환하라 (각 줄: SOUL: 서브태스크):
   {soul}: {subtask}"
   ```
   - `forge run`이 성장/비용을 자동 기록한다. 별도 `log-add` 금지.
   - 마지막 `<usage> ...` 라인은 표시용.
2. 분해 결과를 태스크 리스트로 기록 (`|` 구분):
   ```bash
   GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh mission set-tasks <id> "{t1}|{t2}|{t3}"
   ```

---

## Phase 3: 자율 실행 (execute 루프)

**여기서부터 모드 종료까지, 정지 조건 외에는 사용자에게 묻지 않는다.**

각 태스크에 대해 순회한다:

### Step 3-1: SOUL 실행 가시성 배너 (필수 — 생략 금지)

`forge run` 호출 **전에** 반드시 표시한다:

```
──────────────────────────────────
>> {SOUL_NAME} ({role}) 작업 시작
   태스크: {task_summary}
   모델: {model} | 랭크: {rank} | 도구: {tools}
──────────────────────────────────
```

병렬 실행 시 각 SOUL마다 개별 표시. 이 배너 없이 `forge run`을 호출하지 마라.

### Step 3-2: 태스크 상태 갱신 + SOUL 소환

1. 태스크를 in_progress로:
   ```bash
   GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh mission task <id> <idx> in_progress {soul}
   ```
2. SOUL 소환 (엔진 네이티브 — OMC `Agent(subagent_type=...)` 금지):
   ```bash
   GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh run {soul} "{실제 태스크 내용}"
   ```
   - `forge run`이 frontmatter의 model/tools/maxTurns를 자동 적용하고, 성장·비용을 자동 기록한다.
   - 반환: SOUL 산출물(stdout) + 마지막 줄 `<usage> ... result=...`
3. 성공 시 done, 실패 시 failed로 갱신:
   ```bash
   GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh mission task <id> <idx> done {soul}
   ```

### Step 3-3: 완료 배너 (필수 — 생략 금지)

각 SOUL 종료 후:

```
<< {SOUL_NAME} 완료 — {result} ({files}파일, {tests}테스트)
```

- {result}: `forge run`의 `<usage> ... result=` 값
- {files}/{tests}: `git diff --stat` / 테스트 출력에서 호스트가 집계

### Step 3-4: SOUL 실패 시 — 묻지 말고 복구

`forge run`이 `result=fail` 이거나 비정상 종료하면 **사용자에게 묻지 않고** 3단계 복구를 자동 수행한다:

```bash
GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh recover {soul} "{task}" "{failure_reason}"
```

1회 → 같은 SOUL 재시도 / 2회 → 대체 SOUL 위임 / 3회 → Director 에스컬레이션. 복구 후 루프를 계속한다.

### ⛔ 정지 조건 (이 3가지 외에는 절대 사용자에게 묻지 않는다)

자율 실행 중 **오직 아래 세 경우에만** 멈추고 사용자에게 묻는다:

- **(a) HARD 블로커** — 사용자 입력/크리덴셜/결정 없이는 진짜로 진행 불가 (예: 누락된 API 키, 양자택일 비즈니스 결정).
- **(b) 비가역·파괴적 행위** — force push, 대량 삭제, 외부 배포/publish, 프로덕션 deploy. 실행 전 반드시 확인받는다.
- **(c) 검증 반복 실패** — 아래 Phase 4의 execute↔verify 루프가 **3사이클 이상** 통과하지 못함.

위 셋이 아니면 — **"이렇게 할까요?" 류의 중간 확인을 절대 하지 않는다.** 판단하고 진행한다.

---

## Phase 4: 검증 + 완료 (execute↔verify 루프)

**완료는 증거 기반이다. 호스트가 스스로 "완료"를 선언하지 않는다 — verifier SOUL과 테스트가 확인한다.**

### Step 4-1: 검증 (author ≠ verifier)

실행을 끝낸 SOUL과 **다른** verifier SOUL(Zen 또는 qa role SOUL)을 소환하여 spec의 성공 기준 대비 검증한다:

```
──────────────────────────────────
>> Zen (qa-tester) 작업 시작
   태스크: 성공 기준 대비 검증 + 테스트 실행
   모델: {model} | 랭크: {rank} | 도구: {tools}
──────────────────────────────────
```

```bash
GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh run zen "다음 mission의 성공 기준 대비 결과를 검증하라. 테스트를 실행하고 통과 여부를 보고하라.

성공 기준: {성공 기준}
변경 요약: {git diff --stat 요약}

PASS/FAIL과 근거(실패 시 구체적 원인)를 반환하라."
```

- **author≠verifier 강제**: 작업을 수행한 SOUL은 자기 작업의 verifier가 될 수 없다. 단독(solo) 모드라도 검증은 반드시 별도 verifier SOUL이 수행한다.
- 호스트는 별도로 테스트 명령(프로젝트의 테스트 러너)을 직접 실행해 결과를 수집한다.

### Step 4-2: 루프 판단

- **verifier PASS + 테스트 통과** → Phase 4-3 완료로 진행.
- **FAIL** → 실패 원인을 다음 execute 사이클의 입력으로 주입하고 **Phase 3으로 돌아간다** (해당 태스크를 failed로 표시 후 재실행).
- **3사이클 연속 실패** → 정지 조건 (c). 멈추고 사용자에게 현재 상태·실패 원인·시도 내역을 보고한다.

### Step 4-3: 완료 처리

verifier PASS + 테스트 통과가 확인되면:

```bash
GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh mission complete <id>
```

그 후 **증거와 함께** 최종 보고한다:
- 달성한 성공 기준 (체크 형태)
- verifier SOUL의 PASS 근거
- 테스트 결과 (통과 수치)
- 변경된 파일 목록 (`git diff --stat`)
- 각 SOUL의 `<< {SOUL} 완료` 누적

---

## 예시 실행 흐름

```
사용자: forge mission: 사용자 로그인 API 완성해줘

[Phase 1 — 인터뷰 배치]
호스트가 question UI로 한 번에 묻는다:
  (a) 성공 기준?  (b) 제약·기술?  (c) 비범위?  (d) 우선순위?
→ 사용자: "/login 200+JWT, 통합테스트 통과 / 기존 Express 패턴 / 소셜로그인 제외 / 정확성 우선"

→ mission init "사용자 로그인 API" "/login 200+JWT, 통합테스트 통과" "기존 Express 패턴 유지" "소셜로그인 제외"
   → id: 2026-06-04_사용자-로그인-api

[Phase 2 — 스코프 + 분해]
호스트 판단: 큼(team) → forge run nex 분해
  → "ryn: /login 핸들러+JWT 발급, zen: 통합테스트 작성·검증"
→ mission set-tasks <id> "ryn: /login 핸들러+JWT|zen: 통합테스트"

[Phase 3 — 자율 실행]
──────────────────────────────────
>> Ryn (backend-developer) 작업 시작
   태스크: /login 핸들러+JWT 발급
   모델: sonnet | 랭크: junior | 도구: Read, Edit, Grep, Glob
──────────────────────────────────
→ mission task <id> 0 in_progress ryn
→ forge run ryn "/login 핸들러+JWT 발급"
→ mission task <id> 0 done ryn
<< Ryn 완료 — success (3파일, 0테스트)

[Phase 4 — 검증 (author≠verifier)]
──────────────────────────────────
>> Zen (qa-tester) 작업 시작
   태스크: 성공 기준 대비 검증 + 테스트 실행
──────────────────────────────────
→ forge run zen "성공 기준 대비 검증 + 통합테스트"
→ 테스트 실행: 8 passed
→ verifier: PASS (/login 200+JWT 확인, 통합테스트 통과)
<< Zen 완료 — success (1파일, 8테스트)

→ mission complete <id>

응답: "✅ 완주 — 사용자 로그인 API
 성공 기준 달성: /login 200+JWT ✓, 통합테스트 8 passed ✓
 verifier(Zen) PASS — author≠verifier 분리 확인
 변경: 4파일 (handler.js, jwt.js, routes.js, login.test.js)

---
💡 다음 작업:
  • `forge review ryn` — 코드 리뷰
  • `forge mission status <id>` — 미션 상세
  • `forge status` — 전체 현황"
```

## ⚠️ 필수: 연관 작업 안내

**완주 보고(Phase 4-3) 마지막에 반드시 연관 작업 안내를 포함한다:**
- `forge status` — 전체 현황
- `forge mission status <id>` — 미션 상세 (태스크별 상태)
- `forge review {soul}` — 산출물 코드 리뷰

## forge.sh 호출 규칙 (중요)

**모든 `bash ~/.claude/golem-garden/forge.sh` 호출 시 반드시 `GOLEM_PROJECT="$(pwd)"`를 전달하라.**
누락 시 `.golem/missions/` 프로젝트 경로가 아닌 글로벌에 기록된다.
