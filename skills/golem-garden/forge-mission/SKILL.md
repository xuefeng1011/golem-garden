---
name: forge-mission
description: GolemGarden 단일 목표 완주 모드. 하나의 목적(goal)을 최소 개입으로 완료까지 끌고 간다. 시작 시 일괄 요구사항 인터뷰 → spec 고정 → 결정론 루프(forge mission run) 자율 실행 → 검증·완료.
trigger: forge mission, 포지 미션, forge 미션, forge mission:, 끝까지 해줘, 완주, 하나의 목적, 하나의 목표 완주
---

# forge-mission — 단일 목표 완주 스킬

사용자가 `forge mission: {목표}` 형태로 입력하면 이 스킬이 실행된다.
이 모드의 본질은 **"하나의 목적을 최소 개입으로 완료까지 끌고 가는 것"** 이다.
일반 `forge build`와의 차이: build는 한 번의 분배·실행·보고로 끝나지만, mission은 **목표가 검증으로 확인될 때까지 execute↔verify 루프를 반복**한다.

**루프는 프롬프트가 아니라 엔진이 돈다.** `forge mission run`(lib/mission-loop.sh)이
사이클 상한(3)·태스크 재시도 상한(3)·author≠verifier 가드·예산 센티널·스턱 디텍터를
**코드로 강제**한다. 호스트(LLM)의 몫은 인터뷰·분해·정지 시 재계획·완주 보고다.

## 4대 기둥 (FIXED — 우회 금지)

1. **시작 시 요구사항 인터뷰 = 고정 배치.** 모드 시작 직후 호스트가 질문 UI로 **단 한 번의 배치(3~5개 질문)** 를 던져 목표를 결정화한다.
2. **자율성: 완주한다.** 루프 진입 후에는 엔진이 정지 조건에 걸릴 때까지 사용자에게 묻지 않는다.
3. **완료 = verifier SOUL + 테스트 통과.** `mission run`이 verify 레인(verify.sh)을 자동 호출한다 — author≠verifier는 코드 가드로 강제되고, 통과 시에만 `<promise>COMPLETE</promise>` 센티널이 출력된다.
4. **자동 스코프: 작으면 단독, 크면 팀.** 목표 크기를 판단해 태스크를 1개 또는 여러 개로 분해한다.

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
- **비가역·파괴적 행위**(force push, 대량 삭제, 배포/publish)가 목표에 포함되면 여기서 확인받고 spec 제약에 명시한다 — 루프는 중간에 묻지 않는다.

### Step 1-1: spec 영구화

인터뷰 답변을 받으면 즉시 mission spec으로 영구화한다:

```bash
GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh mission init "{목표}" "{성공 기준}" "{제약·기술}" "{비범위}"
```

- 이 명령은 **mission id를 echo** 하고 `.golem/missions/<id>/spec.md`를 생성한다. **성공 기준은 반드시 채운다** — `mission run`의 verify 게이트가 spec.md의 `## 성공 기준` 섹션을 검증 대상으로 사용한다.
- echo된 `<id>`를 이후 모든 mission 명령에 사용한다. 변수로 잡아둔다.

---

## Phase 2: 스코프 판단 + 태스크 분해

### Step 2-1: 목표 크기 판단 (자동 스코프)

| 크기 | 판단 기준 | 실행 방식 |
|------|----------|----------|
| **작음 (solo)** | 단일 파일/단일 도메인, 자명한 변경 | 태스크 1개, 최적 SOUL 지정 |
| **큼 (team)** | 다중 파일/다중 시스템, 분해 필요 | Nex 분해 → 태스크 여러 개 |

### Step 2-2: 태스크 분해

#### 작음 (solo)
```bash
GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh mission set-tasks <id> "{단일 태스크}"
```

#### 큼 (team)
1. Director(Nex)에게 분해를 위임한다 (model=opus 자동 적용):
   ```bash
   GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh run nex "다음 목표를 완주하기 위한 서브태스크로 분해하라.

   목표: {목표}
   성공 기준: {성공 기준}
   제약: {제약}
   비범위: {비범위}

   JSON 배열 한 개로만 반환하라 (다른 텍스트 금지):
   [{\"task\":\"서브태스크1\"},{\"task\":\"서브태스크2\"}]"
   ```
2. 분해 JSON을 그대로 등록한다 (파이프·따옴표 포함 태스크도 안전):
   ```bash
   GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh mission set-tasks-json <id> '{Nex가 반환한 JSON 배열}'
   ```
   - 폴백: JSON 추출 실패 시 `mission set-tasks <id> "{t1}|{t2}"` (파이프 구분).

---

## Phase 3: 자율 실행 — `forge mission run` (결정론 루프)

**루프 전체가 엔진 1회 호출이다. 호스트가 태스크를 하나씩 소환하지 않는다.**

### Step 3-1: 실행 배너 (필수 — 생략 금지)

`mission run` 호출 **전에** 표시한다:

```
──────────────────────────────────
>> Mission Loop 시작: {목표}
   태스크: {n}건 | 실행: {soul} | 검증: {verifier}
   상한: 3사이클 × 태스크당 3시도 | 예산·스턱 디텍터 활성
──────────────────────────────────
```

### Step 3-2: 루프 소환

```bash
GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh mission run <id> {executor_soul} {verifier_soul}
```

- `{executor_soul}` 생략 시 태스크별 specialty 자동 매칭. **`{verifier_soul}`(기본 zen)은 executor와 달라야 한다** — 같으면 verify 가드가 정지시킨다.
- 엔진이 자동 수행: 태스크 순회(`in_progress→done`), 실패 시 실패 컨텍스트 주입 재시도(3회), 소환마다 예산 기록·판정, 전 태스크 done 시 verify 레인 호출, FAIL 사유를 다음 사이클 프롬프트에 주입, 스턱 감지.
- 성장/비용은 `forge run` 경로가 자동 기록한다. 별도 `log-add` 금지.

### Step 3-3: 종료 코드 판정 (정지 프로토콜)

| rc | 의미 | 호스트의 행동 |
|----|------|--------------|
| 0 | **완주** — `<promise>COMPLETE</promise>` 출력됨 | Phase 4 완주 보고 |
| 1 | 태스크 3회 연속 실패 / 설정 오류 | 실패 태스크를 더 작게 재분해(`set-tasks-json`)하거나 SOUL 교체 후 **`mission run` 재호출** (loop.json이 사이클을 이어받는다). 2회 재계획에도 실패하면 사용자 보고 |
| 2 | 예산 정지 (BUDGET_EXCEEDED/STAGNATING) | 사용자에게 예산 상태(`forge budget status`)와 함께 보고 — 계속할지 결정은 사용자 몫 |
| 3 | STUCK — 진전 없음 | 접근법 자체를 바꿔 재분해 후 재호출, 또는 사용자 보고 |
| 4 | 검증 3사이클 실패 — 정지 조건 (c) | 현재 상태·실패 원인·시도 내역을 사용자에게 보고 |

- HARD 블로커(누락 크리덴셜, 양자택일 결정)가 출력에 보이면 rc와 무관하게 사용자에게 묻는다 — 정지 조건 (a).

---

## Phase 4: 완주 보고

rc=0(`<promise>COMPLETE</promise>` 확인) 후 **증거와 함께** 최종 보고한다:

- 달성한 성공 기준 (체크 형태)
- verify 레인의 `[VERDICT: PASS]` 근거 (mission run 출력에 포함)
- 테스트 결과 (통과 수치)
- 변경된 파일 목록 (`git diff --stat`)
- `mission status <id>` 요약 (태스크별 done)

`mission complete`는 엔진이 자동 호출한다 — 호스트가 따로 부르지 않는다.

---

## 예시 실행 흐름

```
사용자: forge mission: 사용자 로그인 API 완성해줘

[Phase 1 — 인터뷰 배치]
호스트가 question UI로 한 번에 묻는다:
  (a) 성공 기준?  (b) 제약·기술?  (c) 비범위?  (d) 우선순위?
→ mission init "사용자 로그인 API" "/login 200+JWT, 통합테스트 통과" "기존 Express 패턴 유지" "소셜로그인 제외"
   → id: msn_1780xxxxx_1234

[Phase 2 — 스코프 + 분해]
호스트 판단: 큼(team) → forge run nex 분해 (JSON 배열 반환)
→ mission set-tasks-json <id> '[{"task":"/login 핸들러+JWT 발급"},{"task":"통합테스트 작성"}]'

[Phase 3 — 결정론 루프]
──────────────────────────────────
>> Mission Loop 시작: 사용자 로그인 API
   태스크: 2건 | 실행: ryn | 검증: zen
   상한: 3사이클 × 태스크당 3시도 | 예산·스턱 디텍터 활성
──────────────────────────────────
→ forge mission run <id> ryn zen
   [mission] ── task 0 (ryn): /login 핸들러+JWT 발급
   [mission] ── task 1 (ryn): 통합테스트 작성
   [mission] ── verify (author=ryn, verifier=zen)
   [VERDICT: PASS] ...
   <promise>COMPLETE</promise>          ← rc=0

[Phase 4 — 완주 보고]
응답: "✅ 완주 — 사용자 로그인 API
 성공 기준 달성: /login 200+JWT ✓, 통합테스트 8 passed ✓
 verify 레인 PASS (author=ryn ≠ verifier=zen, 코드 가드 강제)
 변경: 4파일 (handler.js, jwt.js, routes.js, login.test.js)

---
💡 다음 작업:
  • `forge review ryn` — 코드 리뷰
  • `forge mission status <id>` — 미션 상세
  • `forge status` — 전체 현황"
```

## ⚠️ 필수: 연관 작업 안내

**완주 보고(Phase 4) 마지막에 반드시 연관 작업 안내를 포함한다:**
- `forge status` — 전체 현황
- `forge mission status <id>` — 미션 상세 (태스크별 상태)
- `forge review {soul}` — 산출물 코드 리뷰

## forge.sh 호출 규칙 (중요)

**모든 `bash ~/.claude/golem-garden/forge.sh` 호출 시 반드시 `GOLEM_PROJECT="$(pwd)"`를 전달하라.**
누락 시 `.golem/missions/` 프로젝트 경로가 아닌 글로벌에 기록된다.
