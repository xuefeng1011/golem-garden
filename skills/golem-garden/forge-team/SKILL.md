---
name: forge-team
description: GolemGarden 팀 단위 작업 실행. SOUL 컨텍스트를 OMC 에이전트에 주입하고 실행한다.
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
2. `GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh prompt-director "{task}"` 실행하여 Director 프롬프트 생성
3. Director(Nex)를 Agent(subagent_type=architect, model=opus)로 실행:
   - 프롬프트에 가용 SOUL 목록(tools/maxTurns/isolation 포함) + 태스크 포함
   - `.golem/analysis.md` 아키텍처 소견이 있으면 추가 컨텍스트로 주입
   - Director가 서브태스크 분배 결과를 반환 (각 SOUL별 isolation 모드 포함)
4. **Director 비용 기록**: Agent 결과에서 `<usage>` 태그의 `total_tokens`, `duration_ms`를 추출하여 기록
   ```bash
   GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh log-add-usage nex "{task} 분배" success 0 0 opus {total_tokens} {duration_ms}
   ```
   - usage 추출 불가 시 `log-add`로 폴백:
   ```bash
   GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh log-add nex "{task} 분배" success 0 0
   ```
5. 반환된 분배 결과에 따라 각 SOUL에 태스크 배정
6. **메일박스 통지**: Director가 각 SOUL에게 task_assign 메시지 전송
   ```bash
   GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh mailbox send nex {soul} task_assign "{subtask}"
   ```

**에러 처리:**
- Director Agent 실패 시: `forge recover nex "{task}" "Director 분배 실패"` 실행
- Director 응답이 SOUL 이름을 포함하지 않을 시: 가용 SOUL 목록 보여주고 사용자에게 선택 요청
- forge.sh prompt-director 실행 실패 시: "GolemGarden 미설치 또는 경로 오류. `forge status`로 확인하세요" 안내

#### 수동 지정 (forge assign)

1. 지정된 SOUL 이름으로 바로 Step 3 진행

### Step 3: SOUL 컨텍스트 주입 + OMC 에이전트 실행

각 배정된 SOUL에 대해:

0. **SOUL 실행 가시성 (필수 — 생략 금지)**:
   Agent 호출 **전에** 반드시 아래 형식으로 사용자에게 표시한다:
   ```
   ──────────────────────────────────
   >> {SOUL_NAME} ({role}) 작업 시작
      태스크: {task_summary}
      모델: {model} | 랭크: {rank} | 도구: {tools}
   ──────────────────────────────────
   ```
   병렬 실행 시 각 SOUL마다 개별 표시. 이 메시지 없이 Agent를 호출하지 마라.

1. **세션 업데이트**: SOUL 상태를 "working"으로 변경
   ```bash
   GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh session log {soul_name} task_start "{task}"
   ```

2. `GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh prompt {soul_name} "{task}"` 실행하여 프롬프트 생성

3. SOUL의 role에 따른 OMC 에이전트 결정:

| SOUL Role | Agent subagent_type | model |
|-----------|-------------------|-------|
| director | architect | opus |
| backend-developer | executor | sonnet |
| frontend-developer | designer | sonnet |
| qa-tester | test-engineer | haiku |
| devops-engineer | executor | sonnet |
| data-analyst | scientist | sonnet |
| technical-writer | writer | haiku |
| security-auditor | security-reviewer | opus |
| knowledge-auditor | executor | sonnet |
| game-logic-developer | executor | sonnet |
| game-designer | planner | sonnet |

4. **Worktree 격리** (SOUL의 isolation=worktree일 때):
   - ultrapilot 모드에서 SOUL의 `isolation` 필드가 `worktree`이면:
   ```bash
   GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh worktree create {soul_name} "{task}"
   ```
   - Agent 실행 시 worktree 경로를 작업 디렉토리로 전달
   - 현재 novice/junior는 `isolation: none`이므로 동일 디렉토리에서 작업
   - senior 이상 승급 시 자동으로 worktree 격리 활성화

5. **도구 제한**: SOUL의 `tools` frontmatter를 Agent의 도구 풀로 전달
   ```
   Agent(
     subagent_type = "{매핑된 에이전트}",
     model = "{SOUL의 model 필드}",
     prompt = "{forge.sh prompt로 생성된 프롬프트}\n\n태스크:\n{실제 태스크 내용}",
     description = "{soul_name}: {task 요약}",
     isolation = "{worktree일 때만 지정}"
   )
   ```
   프롬프트에 이미 `허용 도구: [...]`, `최대 턴: N`이 포함되어 있으므로 Agent가 이를 준수한다.

6. **병렬 실행** (forge build):
   - 병렬 실행 전 도구 성격 체크: `forge tool-char parallel {soul1} {soul2}`
     - `yes` → 안전하게 병렬
     - `conditional` → 파일 영역 분리 필요
     - `worktree_required` → worktree 격리 후 병렬
   - 독립적인 서브태스크는 Agent를 병렬로 호출 (한 메시지에 여러 Agent 호출)
   - 의존성 있는 태스크는 순차 실행
   - **Fork 캐시 최적화**: 병렬 SOUL 소환 시 `prompt_build_fork`로 byte-identical prefix 공유

**에러 처리 (3단계 복구 프로토콜):**
- Worker Agent 1회 실패 시: 같은 SOUL로 재시도 (실패 원인 주입)
   ```bash
   GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh recover {soul_name} "{task}" "{failure_reason}"
   ```
- Worker Agent 2회 실패 시: 대체 SOUL에 위임 (specialty 매칭)
- Worker Agent 3회 실패 시: Director에게 에스컬레이션 → 사용자에게 보고
- forge.sh prompt 실행 실패 시: 해당 SOUL 건너뛰고 사용자에게 알림
- 코드 충돌(동일 파일 수정) 시: 사용자에게 충돌 파일 보여주고 수동 해결 요청

### Step 4: Worktree 머지 (격리 모드일 때)

isolation=worktree로 실행된 SOUL이 있으면:
```bash
GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh worktree merge {soul_name} squash
```
- 변경사항 없으면 자동 정리
- 충돌 시 사용자에게 보고

### Step 5: 결과 기록 (비용 자동 추적)

각 SOUL의 태스크 완료 후:

1. **Agent 결과에서 usage 데이터 추출**: Agent 결과 끝에 포함된 `<usage>` 태그에서 값을 파싱한다.
   ```
   <usage>total_tokens: 50000, tool_uses: 15, duration_ms: 120000</usage>
   ```
   - `total_tokens`: 총 사용 토큰
   - `duration_ms`: 실행 시간 (밀리초)

2. **`log-add-usage`로 비용 포함 기록** (log-add 대신 사용):
   ```bash
   GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh log-add-usage {soul_name} "{task}" {result} {files_changed} {tests_passed} {model} {total_tokens} {duration_ms}
   ```
   - result: "success" 또는 "fail"
   - files_changed: 변경된 파일 수 (git diff --stat로 확인)
   - tests_passed: 통과한 테스트 수
   - model: SOUL의 model 필드 (opus, sonnet, haiku)
   - total_tokens: Agent usage에서 추출한 값
   - duration_ms: Agent usage에서 추출한 값
   - **비용은 자동 계산됨** (모델별 가격 × 토큰 수)
   - **예산 추적도 자동 실행됨** (budget_record)
   - **랭크 체크도 자동 실행됨**

   **usage 데이터를 추출할 수 없는 경우** (Agent 실패 등): 기존 `log-add`로 폴백
   ```bash
   GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh log-add {soul_name} "{task}" {result} {files_changed} {tests_passed}
   ```

   **⚠️ 비용 기록 필수 원칙**: 모든 Agent 호출(Director 분배, Worker 실행, 리뷰)은 반드시 `log-add-usage`로 비용을 기록한다. `log-add`(비용 없음)는 usage 추출 불가 시에만 폴백으로 사용한다.

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

**Step 5의 `log-add` / `log-add-usage` 호출 시 forge-board.md가 자동 업데이트된다.**
별도 호출 불필요 — forge.sh 내부에서 `board_add_task`가 자동 실행됨.

업데이트되는 항목:
- **태스크 히스토리**: 각 SOUL의 작업 결과 + 비용이 자동 누적
- **updated 타임스탬프**: 매 업데이트 시 자동 갱신
- **랭크 변동**: `rank_promote` 시 팀 구성 테이블의 Rank 컬럼 자동 반영

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
   - Agent(executor, sonnet, Ryn 프롬프트 + "인증 API 구현")
   - Agent(designer, sonnet, Kai 프롬프트 + "로그인 화면 구현")
4. (Worktree 머지 — novice이므로 해당 없음)
5. 완료 후:
   - forge log-add-usage ryn "인증 API" success 8 15 sonnet 50000 120000
   - forge log-add-usage kai "로그인 화면" success 3 6 sonnet 35000 80000
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
