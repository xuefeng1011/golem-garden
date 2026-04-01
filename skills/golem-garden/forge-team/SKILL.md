---
name: forge-team
description: GolemGarden 팀 단위 작업 실행. SOUL 컨텍스트를 OMC 에이전트에 주입하고 실행한다.
trigger: forge build, forge quick, forge save, forge assign
---

# forge-team — 팀 실행 스킬

사용자가 `forge build: ...`, `forge quick: ...`, `forge assign {soul}: ...` 형태로 입력하면 실행된다.

## 실행 절차

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

1. `GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh prompt-director "{task}"` 실행하여 Director 프롬프트 생성
2. Director(Nex)를 Agent(subagent_type=architect, model=opus)로 실행:
   - 프롬프트에 가용 SOUL 목록 + 태스크 포함
   - Director가 서브태스크 분배 결과를 반환
3. 반환된 분배 결과에 따라 각 SOUL에 태스크 배정

#### 수동 지정 (forge assign)

1. 지정된 SOUL 이름으로 바로 Step 3 진행

### Step 3: SOUL 컨텍스트 주입 + OMC 에이전트 실행

각 배정된 SOUL에 대해:

1. `GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh prompt {soul_name} "{task}"` 실행하여 프롬프트 생성
2. SOUL의 role에 따른 OMC 에이전트 결정:

| SOUL Role | Agent subagent_type | model |
|-----------|-------------------|-------|
| director | oh-my-claudecode:architect | opus |
| backend-developer | oh-my-claudecode:executor | sonnet |
| frontend-developer | oh-my-claudecode:designer | sonnet |
| qa-tester | oh-my-claudecode:test-engineer | haiku |
| devops-engineer | oh-my-claudecode:executor | sonnet |
| security-auditor | oh-my-claudecode:security-reviewer | opus |

3. Agent tool로 실행:
   ```
   Agent(
     subagent_type = "{매핑된 에이전트}",
     model = "{SOUL의 model 필드}",
     prompt = "{forge.sh prompt로 생성된 프롬프트}\n\n태스크:\n{실제 태스크 내용}",
     description = "{soul_name}: {task 요약}"
   )
   ```

4. **병렬 실행** (forge build):
   - 독립적인 서브태스크는 Agent를 병렬로 호출 (한 메시지에 여러 Agent 호출)
   - 의존성 있는 태스크는 순차 실행

### Step 4: 결과 기록

각 SOUL의 태스크 완료 후:

1. `GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh log-add {soul_name} "{task}" {result} {files_changed} {tests_passed}` 실행
   - result: 에이전트가 성공적으로 완료했으면 "success", 실패하면 "fail"
   - files_changed: 변경된 파일 수 (git diff --stat로 확인)
   - tests_passed: 통과한 테스트 수 (테스트 실행 결과에서 확인)

2. 랭크 체크 자동 실행 (log-add에 포함됨)

### Step 5: 자동 리뷰 트리거

1. `GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh review-auto {soul_name} "{task}"` 실행
   - Novice/Junior SOUL이면 자동으로 리뷰 시작 → forge-review 스킬로 이동
   - Senior 이상이면 건너뜀

### Step 6: 결과 보고

사용자에게 요약 보고:
- 각 SOUL별 태스크 결과
- 변경된 파일 목록
- 테스트 결과
- 랭크 변동 사항

## 예시 실행 흐름

```
사용자: forge build: 사용자 인증 API + 로그인 화면

AI 실행:
1. Director(Nex)에게 분배 의뢰 → "Backend API → Ryn, Frontend UI → Kai"
2. 병렬 실행:
   - Agent(executor, sonnet, Ryn 컨텍스트 + "인증 API 구현")
   - Agent(designer, sonnet, Kai 컨텍스트 + "로그인 화면 구현")
3. 완료 후:
   - GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh log-add ryn "인증 API" success 8 15
   - GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh log-add kai "로그인 화면" success 3 6
4. 자동 리뷰 (둘 다 Novice이므로):
   - forge-review 스킬로 자동 연결

응답: "완료! Ryn: 인증 API (8파일, 15테스트), Kai: 로그인 화면 (3파일, 6테스트)"
```
