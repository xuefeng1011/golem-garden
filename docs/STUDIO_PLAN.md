# Flow Studio — 프로젝트 독립 플로우 설계 (STUDIO_PLAN)

> 상태: 설계 확정 (2026-07-04) · 구현 진행 중
> 관련: FLOW_CONTRACT.md, WEB_UI_PLAN.md, PERF-HARNESS-PLAN.md

## 1. 요건 (사용자 원문 → 기능 매핑)

| # | 사용자 요건 | 기능으로 번역 |
|---|------------|--------------|
| R1 | 기존 플로우 편집기는 프로젝트에 이미 생성된 에이전트로만 동작 — 그대로 두고 "프로젝트 플로우"로 명명, 진행하며 개선 | 기존 FlowEditorView 유지. UI 라벨을 "프로젝트 플로우"로 명확화. 파괴적 변경 없음 |
| R2 | 프로젝트 밖에서 동작하는 완전 독립 플로우 편집기 | **Flow Studio** 신설 — 스튜디오 폴더 = 자기완결 실행 단위, 현재 프로젝트에 영향 0 |
| R3 | 에이전트를 자유 생성 — 모델 지정, 규칙(지침) 부여 가능 | 스튜디오 로컬 SOUL(`<studio>/.golem/souls/*.md`) — name/model/role/규칙 프리폼. 기존 SOUL frontmatter 포맷 그대로 |
| R4 | AI가 알아서 맞춤 에이전트 팀을 생성, 나는 조합·선택만 | **flowsmith** (워크플로우 아키텍트 빌트인 SOUL): 목표 텍스트 → 에이전트 라인업 + 플로우 단계 JSON 제안 → 엔진이 결정론적으로 적용 |
| R5 | 목표만 주면 전문가 에이전트가 필요한 에이전트 소환 + 플로우 완성까지 | `forge studio design <dir> "<goal>"` 1커맨드 = flowsmith 소환 → souls 생성 + flow state.json 생성 |
| R6 | 골렘포지(프로젝트 체계)와 별개로 동작 | 스튜디오 폴더는 git·forge-board·프로젝트 SOUL 불요. 소울 해석은 스튜디오 로컬만 |
| R7 | 하네스 기본 적용 | agent_run 재사용 → effort 타임아웃·예산 preflight·센티널·프로세스 트리 kill·growth-log 자동 적용 |
| R8 | 플로우당 폴더 1개 지정 | `forge studio init <dir>` — 폴더가 곧 스튜디오. 게이트웨이는 이 폴더를 kind="studio" 프로젝트로 등록 |
| R9 | 중간에 에이전트 추가 가능 | `forge studio agent-add` + UI에서 소울 생성/단계 추가 (기존 flow PUT이 done 단계 보존 재작성 지원) |

예시 시나리오: 시장조사 스튜디오(리서처·분석가·요약가), 소설 스튜디오(아이디어 작가·캐릭터 작가·장면 작가·문장 교정가).

## 2. 핵심 아키텍처 결정

**스튜디오 = 자기완결 GOLEM_PROJECT 폴더.** 새 실행 엔진을 만들지 않는다.

```
<스튜디오 폴더>/              ← 사용자가 지정 (플로우당 1폴더)
  studio.json                 ← 마커+메타 {name, goal, created, version}
  .golem/
    souls/                    ← 스튜디오 전용 에이전트 (자유 생성)
    flows/<flow_id>/state.json ← 기존 플로우 엔진 포맷 그대로
    growth-log/  sessions/  mailbox/
  output/                     ← 에이전트 산출물 권장 위치
```

근거:
- `agent_run`/`flow_run`은 `GOLEM_PROJECT`만 바꾸면 임의 폴더에서 동작 (하네스 포함 전부 재사용 = R7 무비용 충족).
- 게이트웨이 `_validate_project_path`는 git/.golem을 요구하지 않음(registry.py:22-66) — $HOME 하위면 등록 가능, 밖이면 `GOLEM_EXTRA_PROJECT_ROOTS`.
- 플로우 CRUD/단건조회/SSE/취소 API 전부 프로젝트 스코프로 이미 존재 — 스튜디오를 프로젝트로 등록하면 즉시 재사용.

**격리 규칙 (R6)**: 스튜디오 실행 시 소울 해석은 `<studio>/.golem/souls/` + 엔진 빌트인(flowsmith)만. 현재 작업 프로젝트의 souls/growth-log를 오염시키지 않음 — cwd가 스튜디오 폴더이므로 구조적으로 보장.

## 3. 엔진 계약 (lib/studio.sh)

모든 서브커맨드는 `[dir]`을 첫 위치 인자로 받되 생략 가능 — 생략 시 `GOLEM_PROJECT`(= 게이트웨이 실행 시 cwd=스튜디오 폴더)를 사용.

```
forge studio init [dir] [name] [goal]     # 스캐폴드 + studio.json + flowsmith 복사 (멱등)
forge studio design [dir] "<goal>"        # flowsmith 소환 → 에이전트 생성 + 플로우 생성
forge studio agent-add [dir] <name> <model> <role> [rules]  # 스튜디오 로컬 소울 생성
forge studio run [dir] [flow_id]          # 최신(또는 지정) 플로우 실행
forge studio status [dir]                 # 스튜디오 요약 (souls/flows)
forge studio list                         # GOLEM_ROOT/studios.jsonl 레지스트리
```

탐색으로 확인된 사실 기반 결정:
- **forge.sh는 빈 폴더에 `.golem/` 자동 스캐폴드** — init은 이를 명시 수행 + `studio.json` + 레지스트리 append.
- **기존 `soul-create`는 `GOLEM_ROOT/souls/`에만 기록** (forge-soul.sh:154) → `studio agent-add`가 스튜디오 스코프 소울 생성기 신설: `<dir>/.golem/souls/<name>.md` (frontmatter: name/model/rank=novice/isolation=none — 스튜디오는 git 불요이므로 worktree 격리 금지) + growth-log 시드.
- **flowsmith는 `templates/souls/flowsmith.md`** 에 정의, `studio init`이 스튜디오 `.golem/souls/`로 복사(bash cp) — 글로벌 souls/ 무오염, 스튜디오 자기완결(R6).
- `studio design` 파이프라인: `agent_run flowsmith "<goal+출력계약>"` → `flow_extract_json`으로 ```json 펜스 추출 →
  `{"agents":[{"name","model","role","rules"}],"steps":[{"id","soul","task","deps":[]}]}` 파싱(json-lite,
  `_json_array_items`를 mission.sh에서 json-lite.sh로 승격 공용화) → agent-add 반복 → 임시 steps 파일 → `flow_create`.
  파싱/검증 실패 시 재질의 1회, 그래도 실패면 rc=1. 단계 task 문자열은 1-depth·`},{` 금지 계약(flow-contract) 준수를 flowsmith 프롬프트에 명시.
- `studio run`: 서브셸에서 `cd <dir>` + `GOLEM_PROJECT=<dir>` 후 `flow_validate && flow_run` — agent_run은 cwd 기준으로 동작하므로 cd 필수(탐색 확인).
- 하네스: agent_run의 effort 타임아웃·예산 preflight·growth-log가 스튜디오 GOLEM_DIR 기준으로 그대로 작동(R7).

## 4. 게이트웨이 계약

- `Project.kind: Literal["project","studio"] = "project"` 필드 추가 (registry.py:69 — 기존 projects.json 후방호환, 저장 payload version 유지).
- `POST /v1/studios {name, path, goal?}`: `_validate_project_path(allow_missing=True)` → **미존재 폴더 자동 생성**(스튜디오는 "새 폴더 지정" UX; 위치 정책 home/`GOLEM_EXTRA_PROJECT_ROOTS`는 동일 적용, 기존 파일 경로는 400) → kind=studio 등록 → `forge studio init` **동기 실행**(api_flows `_validate_with_forge` 서브프로세스 패턴, 30s 상한; 실패 시 등록 롤백 + 500) → Project 반환.
- `GET /v1/studios` = kind=studio 목록. `GET /v1/projects`는 kind=project만 반환 (스튜디오가 기존 프로젝트 화면에 섞이지 않게).
- 화이트리스트: `ALLOWED_FORGE_COMMANDS`(config.py:219)에 `studio` 추가. `_run_timeout_seconds`(forge_runner.py:126): `studio` + `args[:1] in (["run"],["design"])`도 MAX_FLOW_SECONDS.
- flows CRUD·단건조회·souls 목록·forge SSE·취소는 기존 프로젝트 스코프 API를 스튜디오 id로 그대로 사용 (flow run = `POST /forge {command:"flow",args:["run",id]}`, cwd=스튜디오 폴더 — 탐색 확인).

## 5. 클라이언트 계약

- **FlowEditorView 파라미터화 (Option B)**: `const projectId = computed(() => route.params.projectId ?? profilesStore.activeProfile?.id)` — `profilesStore.activeProfile?.id` 참조 12곳을 이 computed로 기계적 치환. 신규 라우트 `hermes.flowStudio.editor = /hermes/flow-studio/:projectId` 가 동일 컴포넌트 재사용. 액티브 프로젝트 전환/리로드 없음 → R6(현 프로젝트 무영향) 충족.
- **FlowStudioView** (신규, `/hermes/flow-studio`): 스튜디오 카드 목록(`GET /v1/studios`) + 생성 위저드(ProfileCreateModal 패턴: 이름+폴더 경로+목표) → `POST /v1/studios` → "AI 팀 생성" 원클릭 = `startForge(studioId,'studio',['design', goal])` + SSE 출력 패널(ProjectInitModal 패턴) → 완료 시 에디터로 이동.
- **에이전트 중간 추가(R9)**: 캔버스 addAgent는 기존 기능. 스튜디오 컨텍스트에 "새 에이전트 생성" 버튼 추가 = 폼(name/model/role/rules) → `startForge(studioId,'studio',['agent-add', ...])` → souls 재조회.
- **라벨(R1)**: `sidebar.flowEditor` → "프로젝트 플로우"(ko) / "Project Flows"(en) 등 8로케일. 신규 `flowStudio.*` 네임스페이스 + i18n 가드 테스트(기존 i18n-flow-editor.test.ts 패턴, raw `{{}}` 금지).
- 사이드바: Flow Studio 최상위 항목 추가.

## 6. 테스트 게이트

- bats: test_studio.bats — init 멱등/design 파싱·적용/agent-add/run 배선/격리(souls 해석 스코프)/flowsmith 출력 재질의.
- pytest: studios API(생성·목록·kind 필터·후방호환 projects.json), whitelist/timeout 회귀.
- vitest: studios api 모듈 + 뷰 스모크. vue-tsc.
- 라이브 스모크: 임시 폴더 스튜디오 생성 → design(소형 목표) → 에이전트/플로우 생성 확인 → run 완주 1건.

## 7. 명시적 제외 (이번 범위 아님)

- 스튜디오 간 템플릿 마켓/공유, 플로우 버전 관리, 크론 스케줄, 스튜디오 전용 대시보드 통계.
- 프로젝트 플로우 편집기의 대규모 개편 (R1은 라벨·소극 개선만).
