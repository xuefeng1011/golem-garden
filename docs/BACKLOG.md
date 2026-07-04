# BACKLOG — 다음 세션 개선 백로그

> 갱신: 2026-07-05 (Flow Studio 출시 직후, main `5f382c2`)
> 직전 완료 트랙: Flow Studio(STUDIO_PLAN.md) + 플로우 신뢰성/관측성 + 3도메인 검수 사이클(실결함 7건 수정)
> 게이트 기준선: bats 319 / pytest 331 / vitest 301 / vue-tsc 클린

## P0 — 스튜디오 기능 완결 갭 (다음 세션 최우선)

### 1. UI 플로우 실행 시 output 규칙 미적용 ★
- **증상**: 편집기의 실행 버튼은 `forge flow run`을 직접 호출한다. `GOLEM_FLOW_OUTPUT_DIR`는
  `studio_run`(lib/studio.sh)만 수출하므로, **UI로 실행하면 에이전트에게 산출물 경로 규칙이
  주입되지 않는다** — CLI(`forge studio run`)로 돌릴 때만 output/ 규칙이 작동.
- **권장 해법**: 엔진 레벨 — `lib/flow.sh`의 `_flow_prepend_context`가
  `GOLEM_FLOW_OUTPUT_DIR` 부재 시 `${GOLEM_PROJECT}/studio.json` 존재 여부를 확인하고
  있으면 `${GOLEM_PROJECT}/output`을 자동 적용. (게이트웨이/클라이언트 무변경으로 해결됨)
- 테스트: test_flow.bats — studio.json 있는 프로젝트에서 flow_run 직접 호출 시 규칙 주입 확인.

### 2. output/ 산출물 브라우저
- 플로우가 만든 파일을 UI에서 볼 방법이 없음.
- 게이트웨이: `GET /v1/projects/{id}/files?dir=output` (읽기 전용, 경로 순회 방어 —
  `_FLOW_DIR_RE` 패턴 참고) + 파일 내용 조회. 클라이언트: 스튜디오/플로우 완료 화면에 목록+뷰어.

### 3. 스튜디오 목록에 goal 표시
- gateway `Project` 모델에 goal 없음 → 목록 API가 `studio.json`을 읽어 goal 포함
  (또는 등록 시 registry에 goal 저장). 클라이언트 카드에 표시.

## P1 — 검수 잔여 (2026-07-05 검수 사이클 LOW, 미수정분)

- **Windows GNU timeout 부재 시 agent_run 벽시계 가드 무제한** (agent-runner.sh 타임아웃 래퍼
  — `timeout`/`gtimeout` 없으면 비활성). 대체 가드: 백그라운드 워치독 킬 or 코스트 캡 기본화.
- 게이트웨이 500 detail이 subprocess stderr 원문 노출 — api_flows/api_studios 공통 redaction.
- `v-model:show` 닫기 가드 패턴 통일 — StudioCreateModal은 수정 완료, ProfileCreateModal·
  ProviderFormModal 등 동일 패턴 잔존 (SSE 가드가 없는 모달이라 저위험이지만 통일 권장).
- studio_run 최신 플로우 선택이 mtime 동초 tie에서 비결정 / soul frontmatter
  `specialty: [role]`의 `]` 포함 role 이스케이프 (둘 다 코스메틱).

## P2 — 이월 (PERF-HARNESS-PLAN.md 참조)

- P2-1 모델 라우팅 테이블 (rank→모델 매핑 정책)
- P1-1 턴 캡 stream 집행 (maxTurns 프롬프트 권고 → 코드 강제)
- P1-3 rubric verify (검증 레인 루브릭 채점)
- 2차 로케일(de/es/fr/ja/pt) flowEditor 네임스페이스 백필 — 현재 en 폴백, 신규 키만 존재
- runs/sessions retention 정책, 글로벌 설치 드리프트 감지(doctor)

## P3 — 스튜디오 확장 아이디어

- 팀 프리셋/템플릿: 소설팀·시장조사팀 등을 domain-pack 방식으로 원클릭 설치
- design 반복: 사용자 피드백을 받아 flowsmith가 기존 팀/플로우를 재설계 (`studio redesign`)
- flowsmith 출력 계약에 rank/effort 지정 허용 (현재 novice 고정)
- 스튜디오 삭제 UI (DELETE /v1/studios/{id} API는 완성, 버튼만 부재)

## 참고 (환경/컨텍스트)

- `GOLEM_EXTRA_PROJECT_ROOTS=C:/01_xuefeng` 사용자 env 설정됨 (스튜디오 경로 정책 허용 루트)
- 첫 실사용 스튜디오: `C:\01_xuefeng\08_ai\flow\xiaoshuo` (소설팀 — 4에이전트, 6단계 플로우 완주)
- 게이트웨이는 글로벌 엔진(`~/.claude/golem-garden/forge.sh`)을 실행 — lib 변경 시 `bash install.sh` 동기화 필수
