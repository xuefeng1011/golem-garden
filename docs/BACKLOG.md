# BACKLOG — 다음 세션 개선 백로그

> 갱신: 2026-07-05 2차 (P0 트랙 완료 반영)
> 직전 완료 트랙: Flow Studio(STUDIO_PLAN.md) + 플로우 신뢰성/관측성 + 검수 사이클 + **P0 3건 완료**
> 게이트 기준선: bats 322+ / pytest 362 / vitest 314 / vue-tsc 클린

## P0 — 스튜디오 기능 완결 갭 → ✅ 전부 완료 (2026-07-05)

1. ~~UI 플로우 실행 시 output 규칙 미적용~~ → `_flow_prepend_context`가 studio.json 감지 시
   `<project>/output` 자동 적용 (env 명시가 우선). 실스튜디오 라이브 확인 완료.
2. ~~output/ 산출물 브라우저~~ → `GET /v1/projects/{id}/artifacts`(목록) + `/artifacts/content`
   (256KiB 캡·바이너리 감지·경로 순회 방어) + ArtifactsDrawer(편집기 툴바·스튜디오 카드 양쪽).
3. ~~스튜디오 목록 goal 표시~~ → GET /v1/studios가 studio.json goal 포함(StudioOut), 카드 2줄 클램프.

## P1 — 검수 잔여 (2026-07-05 검수 사이클 LOW, 미수정분)

- ~~**Windows GNU timeout 부재 시 agent_run 벽시계 가드 무제한**~~ → **해결 확인**:
  9a2a905 이후 소환 경로는 timeout 바이너리와 무관하게 bash 워치독(kill -0 1s 틱 +
  killflag + `_agent_kill_tree`, rc 124 계약)이 항상 가드한다. 이번 세션에서
  오해 유발 "DISABLED/unbounded" 표시를 bash-watchdog 로 정정하고
  test_agent_runner.bats 에 부재 시나리오 회귀 테스트 2건(강제 종료 계약/워치독 정리) 추가.
- ~~게이트웨이 500 detail이 subprocess stderr 원문 노출~~ → **완료**: `redact_stderr` 공용 헬퍼
  (마지막 줄·200자·절대경로 제거), 원문은 서버 로그에만. api_flows/api_studios 적용.
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
