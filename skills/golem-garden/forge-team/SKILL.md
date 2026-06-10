---
name: forge-team
description: GolemGarden 팀 단위 작업 실행. SOUL을 엔진 네이티브 `forge run`으로 직접 소환한다.
trigger: forge build, forge quick, forge save, forge assign, forge 빌드, 포지 빌드, forge 퀵, 포지 퀵, forge 간단, forge 빠르게
---

# forge-team — 팀 실행 스킬

사용자가 `forge build: ...`, `forge quick: ...`, `forge assign {soul}: ...` 형태로 입력하면 실행된다.

## 실행 절차

### Step 0: 세션 생성 + 예산 초기화

모든 forge-team 실행은 세션으로 추적되고, 예산 추적이 시작된다:

```bash
GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh budget init
```

**예산 체크**: 각 SOUL 턴 완료 후 `forge budget check` 실행
- `ok` → 계속 진행
- `warning` → 사용자에게 경고 표시, 계속 진행
- `exceeded` → 자동 중단, 사용자에게 보고
- `stagnating` → 접근법 변경 권고 또는 중단

모든 forge-team 실행은 세션으로 추적된다:

```bash
GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh session create "{task}" "{soul1,soul2,...}"
```

이후 각 단계에서 세션 이벤트를 기록한다.

### Step 1: 모드 판별

사용자 입력에서 실행 모드를 결정한다:

| 입력 패턴 | 모드 | 분배 방식 |
|----------|------|----------|
| `forge build: {task}` | ultrapilot | Director가 자동 분배 → 병렬 실행 |
| `forge quick: {task}` | autopilot | 최적 SOUL 1개 자동 선택 → 단독 실행 |
| `forge save: {task}` | ecomode | haiku 모델로 비용 절약 실행 |
| `forge assign {soul}: {task}` | 수동 | 지정 SOUL만 단독 실행 |
| `forge build: {task}, {soul} 리드` | 리드 지정 | 리드 SOUL + 나머지 자동 |

### Step 2: SOUL 로드 및 분배

#### 자동 분배 (forge build)

1. `.golem/analysis.md`가 존재하면 Read로 읽어 아키텍처 컨텍스트를 확보한다
2. 가용 SOUL 목록을 확보한다 (`forge status` 또는 `.golem/souls/` 스캔 — tools/maxTurns/isolation 포함)
3. Director(Nex)를 엔진 네이티브 `forge run`으로 직접 소환하여 분배를 받는다:
   ```bash
   GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh run nex "다음 태스크를 서브태스크로 분해하고 각 서브태스크를 가용 SOUL에 배정하라.

   태스크: {task}

   가용 SOUL (역할 / 랭크 / isolation):
   {soul1} ({role}, {rank}, isolation={none|worktree})
   {soul2} (...)
   ...

   {.golem/analysis.md 아키텍처 소견이 있으면 여기에 주입}

   다음 형식으로 분배 결과만 반환하라 (각 줄: SOUL: 서브태스크):
   {soul}: {subtask}"
   ```
   - `forge run`은 SOUL frontmatter의 model(opus 등)/tools를 자동 적용하므로 Agent 매핑이 불필요하다
   - **비용/성장 기록은 `forge run`이 자동 수행**한다 (내부 growth_log_append). 별도 `log-add` / `log-add-usage` 호출 금지 — 중복 기록됨
   - Nex의 stdout 마지막 `<usage> ...` 라인은 표시용이며 별도 기록 불필요
4. **호스트가 인라인 분배해도 무방**: 태스크가 단순해 분배가 자명하면 위 `forge run nex` 단계를 생략하고 호스트가 직접 SOUL 배정을 결정해도 된다 (불필요한 Nex 소환 비용 절감). 분배가 복잡하거나 아키텍처 판단이 필요하면 반드시 `forge run nex`로 위임한다
5. 분배 결과에 따라 각 SOUL에 태스크 배정
6. **메일박스 통지**: Director가 각 SOUL에게 task_assign 메시지 전송
   ```bash
   GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh mailbox send nex {soul} task_assign "{subtask}"
   ```

**에러 처리:**
- `forge run nex` 실패 시: `forge recover nex "{task}" "Director 분배 실패"` 실행
- Director 응답이 SOUL 이름을 포함하지 않을 시: 가용 SOUL 목록 보여주고 사용자에게 선택 요청
- `forge run` 실행 실패(명령 없음/경로 오류) 시: "GolemGarden 미설치 또는 경로 오류. `forge status`로 확인하세요" 안내

#### 수동 지정 (forge assign)

1. 지정된 SOUL 이름으로 바로 Step 3 진행

### Step 3: SOUL 직접 소환 (`forge run`)

각 배정된 SOUL에 대해:

0. **SOUL 실행 가시성 (필수 — 생략 금지)**:
   `forge run` 호출 **전에** 반드시 아래 형식으로 사용자에게 표시한다:
   ```
   ──────────────────────────────────
   >> {SOUL_NAME} ({role}) 작업 시작
      태스크: {task_summary}
      모델: {model} | 랭크: {rank} | 도구: {tools}
   ──────────────────────────────────
   ```
   병렬 실행 시 각 SOUL마다 개별 표시. 이 메시지 없이 `forge run`을 호출하지 마라.

1. **세션 업데이트**: SOUL 상태를 "working"으로 변경
   ```bash
   GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh session log {soul_name} task_start "{task}"
   ```

2. **SOUL 소환**: 엔진 네이티브 `forge run`으로 SOUL 에이전트를 직접 실행한다.
   ```bash
   GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh run {soul_name} "{실제 태스크 내용}" {session_id}
   ```
   - `forge run`이 SOUL frontmatter를 읽어 **model / tools / 시스템 프롬프트를 자동 조립**한다 (OMC 에이전트 매핑 불필요 — `soul_to_omc_agent`는 폐기됨). `maxTurns`는 claude CLI 플래그 미지원으로 프롬프트 내 권고 텍스트로만 전달된다 (강제 아님)
   - SOUL은 self-describing: backend/frontend/qa/devops 등 role 구분 없이 동일하게 `forge run {soul}`로 소환
   - 반환값: SOUL의 최종 산출물(stdout) + 마지막 줄 `<usage> soul=... model=... result=... tokens_in=... tokens_out=... duration_ms=...`
   - **성장 기록/비용은 `forge run`이 내부적으로 자동 기록**한다 (growth_log_append). Step 5에서 별도 `log-add` 금지

3. **Worktree 격리** (SOUL의 isolation=worktree일 때):
   - ultrapilot 모드에서 SOUL의 `isolation` 필드가 `worktree`이면:
   ```bash
   GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh worktree create {soul_name} "{task}"
   ```
   - `forge run` 실행 시 worktree 경로에서 작업하도록 `GOLEM_PROJECT`를 worktree 경로로 전달
   - 현재 novice/junior는 `isolation: none`이므로 동일 디렉토리에서 작업
   - senior 이상 승급 시 자동으로 worktree 격리 활성화

4. **병렬 실행** (forge build):
   - 병렬 실행 전 도구 성격 체크: `forge tool-char parallel {soul1} {soul2}`
     - `yes` → 안전하게 병렬
     - `conditional` → 파일 영역 분리 필요
     - `worktree_required` → worktree 격리 후 병렬
   - 독립적인 서브태스크는 `forge run`을 병렬로 호출 (한 메시지에 여러 Bash 호출)
   - 의존성 있는 태스크는 순차 실행
   - **Novice/Junior SOUL은 동일 파일 병렬 쓰기 금지** — 파일 충돌 위험. 파일 영역을 분리하거나 순차 실행한다

**에러 처리 (3단계 복구 프로토콜):**
- `forge run` 1회 실패 시 (`<usage> ... result=fail` 또는 비정상 종료): 같은 SOUL로 재시도 (실패 원인 주입)
   ```bash
   GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh recover {soul_name} "{task}" "{failure_reason}"
   ```
- 2회 실패 시: 대체 SOUL에 위임 (specialty 매칭) → `forge run {대체_soul} "{task}"`
- 3회 실패 시: Director에게 에스컬레이션 → 사용자에게 보고
- `forge run` 명령 자체가 실패(미설치/경로 오류) 시: 해당 SOUL 건너뛰고 사용자에게 알림
- 코드 충돌(동일 파일 수정) 시: 사용자에게 충돌 파일 보여주고 수동 해결 요청

### Step 4: Worktree 머지 (격리 모드일 때)

isolation=worktree로 실행된 SOUL이 있으면:
```bash
GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh worktree merge {soul_name} squash
```
- 변경사항 없으면 자동 정리
- 충돌 시 사용자에게 보고

### Step 5: 결과 처리 (비용·성장 기록은 `forge run`이 자동 수행)

각 SOUL의 태스크 완료 후:

1. **성장/비용 기록은 자동** — 별도 호출 금지:
   `forge run`은 SOUL 실행 성공 시 내부적으로 `growth_log_append`를 호출하여 **성장 기록 + 비용(토큰×모델 가격) + 예산 추적 + 자동 승급 + 업적 체크 + forge-board 갱신을 모두 자동 수행**한다.
   - 따라서 **여기서 `log-add` / `log-add-usage`를 다시 호출하면 중복 기록된다 → 절대 호출하지 마라.**
   - usage 값(`<usage>` 라인)은 사용자 표시용으로만 파싱한다 (Step 7 완료 배너).
   - 단, `forge run`은 files_changed / tests_passed를 알 수 없어 성장 로그에는 0으로 기록된다. 사용자 보고용 파일/테스트 수치는 호스트가 `git diff --stat` 및 테스트 출력에서 직접 집계하여 표시한다 (성장 로그 재기록 아님).

2. **자동 학습 추출 (lesson-extractor)**:
   SOUL의 산출물을 분석하여 의미 있는 학습만 자동 기록한다.
   
   **추출 기준** (아래 중 하나라도 해당하면 기록):
   - 버그 패턴: 근본 원인 + 해결법 발견
   - 성능 개선: 측정 가능한 기법
   - 프레임워크 함정: 문서에 없는 주의사항
   - 아키텍처 결정: 트레이드오프 수반한 선택
   - 실패 교훈: 회피 패턴 발견
   - 새로운 기법: 처음 사용한 도구/패턴
   
   **건너뛰는 경우**: 단순 CRUD, 설정 변경, 타이포 수정, 일반 상식
   
   학습이 있으면:
   ```bash
   GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh memory record {soul_name} "{task}" "{lesson}" "{tags}"
   ```
   - lesson: 한 줄, 100자 이내, 구체적 기술 내용
   - tags: 쉼표 구분 검색 키워드 3-5개 (예: "jwt,auth,refresh-token")
   - 한 태스크에서 최대 2개 학습까지
   - 실패 태스크도 추출 (실패 원인 자체가 학습)

3. **메일박스 통지**: SOUL이 Director에게 완료 보고
   ```bash
   GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh mailbox send {soul_name} nex task_done "{task} 완료"
   ```

4. **세션 업데이트**: SOUL 상태를 "done"으로 변경

### Step 6: 자동 리뷰 트리거 (선택적)

**중요: 리뷰는 빌드 완료 후 별도 단계로만 실행. 리뷰 결과로 인한 재빌드(forge assign)는 절대 자동 트리거하지 않는다.**

1. `GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh review-auto {soul_name} "{task}"` 실행
   - Novice/Junior SOUL이면 리뷰 필요 여부만 알려줌
   - Senior 이상이면 건너뜀
2. 리뷰가 필요한 경우, **결과 보고에 리뷰 권고 사항만 포함**한다
3. **리뷰 실행은 사용자가 `forge review`로 별도 요청해야 한다** (자동 실행 금지)

### Step 6.5: forge-board.md 자동 업데이트

**자동 갱신 범위 (2026-06-11 정정 — 이전 문서의 "태스크 히스토리 자동 누적" 주장은 미구현이었음):**
- **updated 타임스탬프**: `forge run` 성공 시 `growth_log_append` → `board_update_timestamp` 자동 갱신
- **태스크 히스토리 행 추가**: 리뷰(`forge-review.sh`)와 랭크 승급(`rank-system.sh`) 이벤트만 자동 추가 — 매 run 추가는 보드 범람이라 의도적으로 제외
- **랭크 변동**: `rank_promote` 시 팀 구성 테이블의 Rank 컬럼 자동 반영

주목할 일반 태스크를 보드에 남기려면 호스트가 명시 호출한다 (선택):
```bash
GOLEM_PROJECT="$(pwd)" bash -c 'source ~/.claude/golem-garden/lib/soul-parser.sh && source ~/.claude/golem-garden/lib/forge-board.sh && board_add_task "$(date +%Y-%m-%d)" "{task}" "{soul}" "success"'
```

### Step 7: 세션 종료 + 결과 보고 (빌드 종료 시그널)

**이 단계를 출력하면 forge-build가 완전히 종료된다. 추가 forge 명령을 자동으로 실행하지 않는다.**

1. 세션 종료:
   ```bash
   GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh session end completed
   ```

2. 사용자에게 SOUL별 완료 결과를 표시한다 (필수):
   ```
   << {SOUL_NAME} 완료 — {result} ({files}파일, {tests}테스트, ${cost})
   ```
   - {result}: `forge run`의 `<usage> ... result=` 값
   - {files}/{tests}: `git diff --stat` / 테스트 출력에서 호스트가 집계
   - {cost}: `forge run`이 자동 기록한 값 (`forge dashboard --cost`로 확인 가능 — 표시 생략 가능)

   각 SOUL마다 개별 표시 후 전체 요약:
   - 변경된 파일 목록
   - 테스트 결과
   - 랭크 변동 사항
   - Worktree 머지 결과 (해당 시)
   - (리뷰 필요 시) "리뷰 권고: `forge review {soul}`로 실행하세요"

**⛔ 종료 규칙:**
- Step 7 출력 후 forge-team 스킬은 완료 상태
- 추가 forge 명령(forge assign, forge review 등)을 자동 호출하지 않는다
- 사용자의 다음 입력을 기다린다

## 예시 실행 흐름

```
사용자: forge build: 사용자 인증 API + 로그인 화면

AI 실행:
0. 세션 생성: forge session create "사용자 인증 API + 로그인 화면" "nex,ryn,kai"
1. .golem/analysis.md Read (있으면 아키텍처 컨텍스트 확보)
2. Director(Nex)에게 분배 의뢰 → "Backend API → Ryn, Frontend UI → Kai"
   - mailbox send nex ryn task_assign "인증 API 구현"
   - mailbox send nex kai task_assign "로그인 화면 구현"
3. SOUL 실행 가시성 표시 + 병렬 실행:
   ──────────────────────────────────
   >> Ryn (backend-developer) 작업 시작
      태스크: 인증 API 구현
      모델: sonnet | 랭크: junior | 도구: Read, Edit, Grep, Glob
   ──────────────────────────────────
   >> Kai (frontend-developer) 작업 시작
      태스크: 로그인 화면 구현
      모델: sonnet | 랭크: novice | 도구: Read, Edit, Grep, Glob
   ──────────────────────────────────
   - forge run ryn "인증 API 구현"   (model/tools 자동, 성장·비용 자동 기록)
   - forge run kai "로그인 화면 구현"  (병렬 — 파일 영역 분리됨)
4. (Worktree 머지 — novice이므로 해당 없음)
5. 완료 후 (성장/비용은 forge run이 이미 자동 기록 — log-add 호출 안 함):
   - mailbox send ryn nex task_done "인증 API 완료"
   - mailbox send kai nex task_done "로그인 화면 완료"
6. 리뷰 권고 (둘 다 Novice이므로):
   - "리뷰 권고: `forge review ryn`, `forge review kai`로 실행하세요"
   - ⛔ 자동 리뷰 실행하지 않음
7. 세션 종료 + 결과 보고

응답:
   << Ryn 완료 — success (8파일, 15테스트, $0.045)
   << Kai 완료 — success (3파일, 6테스트, $0.028)
   세션: 2026-04-02_사용자-인증-api-+-로그인-화면 (completed)

---
💡 다음 작업:
  • `forge review ryn` / `forge review kai` — 코드 리뷰
  • `forge dashboard --cost` — 비용 확인
  • `forge status` — 전체 현황"
```

## ⚠️ 필수: 연관 작업 안내

**빌드 결과 보고(Step 7) 마지막에 반드시 연관 작업 안내를 포함한다.**
이 규칙은 forge build, forge quick, forge assign 모두에 적용된다:
- 리뷰 대상이 있으면 `forge review {soul}`을 첫 번째로
- `forge dashboard --cost` — 비용 확인
- `forge status` — 전체 현황
