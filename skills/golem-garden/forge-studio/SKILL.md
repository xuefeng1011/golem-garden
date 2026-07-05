---
name: forge-studio
description: GolemGarden 독립 플로우 스튜디오 모드. 현재 프로젝트와 완전히 분리된 자기완결 폴더에서, 목표만 주면 flowsmith가 맞춤 에이전트 팀과 플로우를 설계·실행한다. 시장조사/소설 창작 등 프로젝트 밖 멀티에이전트 워크플로우용.
trigger: forge studio, 포지 스튜디오, 스튜디오, 독립 플로우, 나만의 플로우, flow studio, studio
---

# forge-studio — 독립 플로우 스튜디오 스킬

사용자가 "스튜디오 만들어줘", "독립 플로우", "나만의 플로우 짜고 싶어", 또는 프로젝트와 무관한
멀티에이전트 워크플로우(시장조사: 리서처·분석가·요약가 / 소설 창작: 아이디어 작가·캐릭터 작가·
장면 작가·문장 교정가 등)를 원할 때 이 스킬이 트리거된다.

**본질**: 스튜디오 폴더 = 자기완결 `GOLEM_PROJECT`. 현재 작업 중인 프로젝트의 `.golem/`
(souls, growth-log, forge-board)에는 어떤 영향도 주지 않는다 — cwd/dir을 스튜디오 폴더로
고정하는 것만으로 구조적으로 격리된다. 새 실행 엔진이 아니라 기존 `agent_run`/`flow_run`을
재사용하므로 effort 타임아웃·예산 가드·growth-log가 스튜디오 안에서도 그대로 동작한다.

일반 `forge build`/`forge mission`과의 차이: 그것들은 **현재 프로젝트 안에서** SOUL을 쓰지만,
studio는 **프로젝트 밖의 별도 폴더**에서 처음부터 끝까지(에이전트 팀 설계 포함) 자율로 돌아간다.

## 4대 원칙 (FIXED — 우회 금지)

1. **플로우당 폴더 1개.** 스튜디오는 반드시 사용자가 지정한 폴더 하나에 대응한다. 폴더를
   확정받지 않고 `studio init`을 호출하지 않는다.
2. **팀 설계는 flowsmith에게 위임한다.** 호스트(LLM)가 직접 에이전트 라인업을 짜지 않는다 —
   `studio design`이 flowsmith(빌트인 워크플로우 아키텍트 SOUL)를 소환해 결정론적으로 적용한다.
3. **소울 파일은 절대 직접 만들지 않는다.** 스튜디오 로컬 SOUL(`<dir>/.golem/souls/*.md`)은
   `studio design`(자동) 또는 `studio agent-add`(수동 보강)로만 생성한다. Edit/Write 금지.
4. **현재 프로젝트 `.golem`은 건드리지 않는다.** 모든 `studio` 명령은 스튜디오 `[dir]`을
   명시하여 호출한다 — 현재 프로젝트의 `GOLEM_PROJECT="$(pwd)"` 패턴을 여기서는 쓰지 않는다.

---

## Phase 1: 인터뷰 — 폴더 확정 + 목표 구체화 (고정 배치)

**모드 시작 직후, 호스트의 질문 UI로 한 번에 묻는다.** 스튜디오는 되돌리기 어려운 폴더
생성 행위이므로 인터뷰를 생략하지 않는다.

```
독립 플로우 스튜디오를 만들기 전에 확정하겠습니다:

(a) 폴더 — 이 스튜디오가 쓸 폴더 경로를 알려주세요 (플로우당 폴더 1개, 새 폴더 권장).
    예: "C:\Users\me\studios\market-research" 또는 "~/studios/novel-writing"

(b) 이름 — 스튜디오를 뭐라고 부를까요?
    예: "시장조사 스튜디오", "소설 창작 스튜디오"

(c) 목표 — 이 스튜디오가 무엇을 완성해야 하나요? 구체적으로 알려주세요.
    예: "국내 스마트워치 시장 경쟁사 3곳 조사 후 SWOT 요약 보고서 작성"
    예: "단편 소설 초고 — SF 장르, 주인공은 은퇴한 우주비행사"

(d) [선택] 이미 원하는 에이전트 구성이 있나요? 없으면 flowsmith가 전부 설계합니다.
```

- **(a) 폴더는 반드시 사용자에게 명시적으로 지정받는다** — 호스트가 임의로 경로를 정하지 않는다.
  기존 폴더를 재사용해도 되지만, 그 폴더는 이 스튜디오 전용이어야 한다(다른 프로젝트와 공유 금지).
- (b)(c)는 목표 문장에 이미 답이 포함되어 있으면 확인 형태로 묻고 생략하지 않는다.
- 답변을 받으면 변수로 고정한다: `{dir}`, `{name}`, `{goal}`.

---

## Phase 2: 스캐폴드 — `studio init`

```bash
bash ~/.claude/golem-garden/forge.sh studio init "{dir}" "{name}" "{goal}"
```

- 멱등 명령이다 — 이미 스캐폴드된 폴더에 다시 호출해도 안전하다.
- `{dir}/studio.json` + `{dir}/.golem/{souls,flows,growth-log,sessions,mailbox}/` + flowsmith
  SOUL 복사가 이 한 번의 호출로 끝난다.
- 실행 전 표시 (SOUL 실행 가시성 규칙과 동일한 취지 — 생략 금지):
  ```
  ──────────────────────────────────
  >> Flow Studio 스캐폴드: {name}
     폴더: {dir}
     목표: {goal}
  ──────────────────────────────────
  ```
- 실패 시(경로 권한 오류 등) 원인을 사용자에게 그대로 보여주고 다른 경로를 다시 묻는다.

---

### Phase 2.5: 프리셋으로 시작 (선택) — `studio preset`

목표가 빌트인 프리셋(소설 창작, 시장조사 등)과 맞으면 flowsmith 설계 대신
검증된 팀으로 바로 시작할 수 있다 — **프리셋으로 시작 → design/redesign 으로 다듬기**:

```bash
bash ~/.claude/golem-garden/forge.sh studio preset list                       # 프리셋 목록
bash ~/.claude/golem-garden/forge.sh studio preset apply "{dir}" {preset_id}  # 원클릭 적용
```

- 빌트인: `novel-team`(소설팀 4인, 세계관→플롯→초고→검수∥교정→최종 6단계),
  `market-research`(시장조사팀 3인, 조사→분석→보고서).
- 미초기화 폴더면 자동으로 init 된다. 적용 후 팀이 목표와 어긋나면 Phase 3(design 전면 재설계)
  또는 Phase 3.6(redesign 피드백 반영)으로 다듬는다.

---

## Phase 3: 팀 설계 — `studio design`

```bash
bash ~/.claude/golem-garden/forge.sh studio design "{dir}" "{goal}"
```

실행 전 표시:
```
──────────────────────────────────
>> flowsmith (워크플로우 아키텍트) 작업 시작
   태스크: "{goal}" 기반 에이전트 팀 + 플로우 설계
   모델: (flowsmith SOUL frontmatter 기준) | 대상 폴더: {dir}
──────────────────────────────────
```

- flowsmith가 목표를 분석해 에이전트 라인업(name/model/role/rules)과 플로우 단계를 제안하고,
  엔진이 파싱해 `agent-add` 반복 + `flow_create`까지 결정론적으로 적용한다.
- **파싱/검증 실패 시 엔진이 자체적으로 1회 재질의한다.** 그래도 실패하면 rc=1을 반환한다 —
  이 경우 목표 문장을 더 구체화해 사용자에게 재확인 후 `studio design`을 다시 호출한다
  (임의로 소울 파일을 손으로 만들어 우회하지 않는다).
- 성공하면 생성된 에이전트 팀 구성을 **사용자에게 요약 보고**한다:
  ```
  << flowsmith 완료 — 에이전트 {n}명 + 플로우 {flow_id} 생성
     - {agent1} ({model}, {role})
     - {agent2} ({model}, {role})
     ...
  ```
- 사용자가 팀 구성을 보고 보강/교체를 요청하면 Phase 3.5로 진행한다. 만족하면 Phase 4로.

### Phase 3.5: 팀 보강 (선택) — `studio agent-add`

중간에 에이전트를 추가하고 싶다는 요청이 오면(R9), design을 다시 돌리지 않고 개별 추가한다:

```bash
bash ~/.claude/golem-garden/forge.sh studio agent-add "{dir}" "{name}" "{model}" "{role}" "{rules}" "{rank}" "{effort}"
```

- `{rules}`는 선택 — 이 에이전트가 지켜야 할 추가 지침(자유 텍스트).
- `{rank}`는 선택 — `novice|junior|senior|expert|master` (기본 novice). 판단/검증 역할엔 senior 이상.
- `{effort}`는 선택 — `low|medium|high` (지정 시에만 frontmatter 에 기록). 판단/검증엔 high, 단순 정형엔 low.
- 추가 후 다시 요약 보고(위 형식)로 사용자에게 확인시킨다.
- 이 명령이 스튜디오 로컬 SOUL 파일을 생성하는 유일한 정식 경로다. Edit/Write로 직접
  `.golem/souls/*.md`를 만들지 않는다.

### Phase 3.6: 재설계 (선택) — `studio redesign`

팀 구성/플로우에 대한 사용자 피드백이 오면 design 을 처음부터 다시 돌리지 않고 재설계한다:

```bash
bash ~/.claude/golem-garden/forge.sh studio redesign "{dir}" "{피드백}"
```

- flowsmith 가 현재 목표 + 팀 로스터 + 최신 플로우 단계 요약을 컨텍스트로 받아 재설계한다.
- **기존 에이전트는 보존(유지)되고 새 에이전트만 추가된다.** 플로우는 항상 새로 생성되며
  기존 플로우 state 는 불변이다 — 이전 플로우로 돌아가려면 `studio run "{dir}" {이전 flow_id}`.
- 완료 시 유지/신규 에이전트 목록과 새 flow_id 를 사용자에게 보고한다.

---

## Phase 4: 실행 — `studio run`

```bash
bash ~/.claude/golem-garden/forge.sh studio run "{dir}" [flow_id]
```

- `flow_id`를 생략하면 최신 플로우를 실행한다.
- 실행 전 표시:
  ```
  ──────────────────────────────────
  >> Flow Studio 실행: {name}
     폴더: {dir} | 플로우: {flow_id 또는 "최신"}
  ──────────────────────────────────
  ```
- **rc 판정**:
  | rc | 의미 | 호스트의 행동 |
  |----|------|--------------|
  | 0 | 완료 또는 승인 대기 | 산출물 위치(`{dir}/output/` 권장) + 각 단계 결과를 사용자에게 보고. 출력에 `[FLOW] 승인 대기`가 있으면 완료가 아니라 승인 게이트 일시정지 — 해당 step 을 확인시키고 승인 절차를 안내 |
  | 비0 | 플로우 실패 | `bash ~/.claude/golem-garden/forge.sh studio status "{dir}"`로 상태 확인 후, 실패한 단계/사유를 사용자에게 보고. 임의 재작성 대신 필요하면 `agent-add`로 팀을 보강하거나 `studio design`을 목표를 다듬어 재호출 |

완료 보고 형식(Phase 3의 `<<` 표시와 통일):
```
<< Flow Studio 완료 — {result} ({dir})
```

---

## 보조 명령

```bash
bash ~/.claude/golem-garden/forge.sh studio status "{dir}"              # souls/flows 요약
bash ~/.claude/golem-garden/forge.sh studio list                        # 등록된 전체 스튜디오 (GOLEM_ROOT/studios.jsonl)
bash ~/.claude/golem-garden/forge.sh studio preset list                 # 빌트인 팀 프리셋 목록
bash ~/.claude/golem-garden/forge.sh studio preset apply "{dir}" {id}   # 프리셋 팀+플로우 원클릭 적용
bash ~/.claude/golem-garden/forge.sh studio redesign "{dir}" "{피드백}"  # 기존 팀 유지 + 재설계 (새 플로우)
```

## 명시적 금지 사항 (재확인)

- 스튜디오 SOUL 파일을 Edit/Write로 직접 생성/수정하지 않는다 — `studio agent-add`만 사용.
- 스튜디오 명령에 현재 프로젝트의 `GOLEM_PROJECT="$(pwd)"`를 섞어 쓰지 않는다 — `[dir]`을
  항상 명시적으로 전달해 현재 프로젝트 `.golem`과 완전히 분리한다.
- `studio init`/`design`을 사용자 확인 없이 임의 경로에 실행하지 않는다 (Phase 1 인터뷰 필수).

## 예시 실행 흐름

```
사용자: 스튜디오 만들어줘, 경쟁사 시장조사 자동으로 돌리고 싶어

[Phase 1 — 인터뷰]
호스트가 한 번에 묻는다: (a) 폴더? (b) 이름? (c) 목표? (d) 원하는 에이전트 있나?
→ dir="~/studios/market-research", name="시장조사 스튜디오",
   goal="국내 스마트워치 시장 경쟁사 3곳 조사 후 SWOT 요약 보고서 작성"

[Phase 2 — 스캐폴드]
──────────────────────────────────
>> Flow Studio 스캐폴드: 시장조사 스튜디오
   폴더: ~/studios/market-research
   목표: 국내 스마트워치 시장 경쟁사 3곳 조사 후 SWOT 요약 보고서 작성
──────────────────────────────────
→ studio init "~/studios/market-research" "시장조사 스튜디오" "국내 스마트워치 시장 ..."

[Phase 3 — 팀 설계]
──────────────────────────────────
>> flowsmith (워크플로우 아키텍트) 작업 시작
   태스크: 목표 기반 에이전트 팀 + 플로우 설계
   대상 폴더: ~/studios/market-research
──────────────────────────────────
→ studio design "~/studios/market-research" "국내 스마트워치 시장 ..."
<< flowsmith 완료 — 에이전트 3명 + 플로우 flow_abc123 생성
   - researcher (sonnet, 리서처)
   - analyst (sonnet, 분석가)
   - summarizer (haiku, 요약가)

사용자: 괜찮은데 팩트체커 하나 더 추가해줘
→ studio agent-add "~/studios/market-research" factchecker sonnet "팩트체커" "모든 수치에 출처 표기"
<< 팀 구성 갱신 — 에이전트 4명

[Phase 4 — 실행]
──────────────────────────────────
>> Flow Studio 실행: 시장조사 스튜디오
   폴더: ~/studios/market-research | 플로우: 최신
──────────────────────────────────
→ studio run "~/studios/market-research"
<< Flow Studio 완료 — success (~/studios/market-research)
   산출물: ~/studios/market-research/output/swot-report.md

---
💡 다음 작업:
  • `forge studio status "~/studios/market-research"` — 상태 확인
  • `forge studio agent-add ...` — 에이전트 보강 후 재실행
  • `forge studio list` — 전체 스튜디오 목록
```

## ⚠️ 필수: 연관 작업 안내

완료 보고(Phase 4) 마지막에 반드시 연관 작업 안내를 포함한다:
- `forge studio status "{dir}"` — 스튜디오 상태 확인
- `forge studio agent-add ...` — 팀 보강 후 재실행
- `forge studio list` — 전체 스튜디오 목록
