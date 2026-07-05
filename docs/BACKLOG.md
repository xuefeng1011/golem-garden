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
- ~~`v-model:show` 닫기 가드 패턴 통일~~ → **완료**: NModal 직접 사용 10개 파일 전부
  one-way `:show` + `@close`/`@mask-click` 패턴으로 통일 (loading 가드 보존).
- ~~studio_run mtime tie / specialty 이스케이프~~ → **완료**: `-nt` 비교 + 사전순 tie-break,
  specialty 값 `[]`,`,` 정화(role: 라인은 원문 유지).

## P2 — 이월 → ✅ 전부 완료 (2026-07-05, retention 제외)

- ~~P2-1 모델 라우팅~~ → `lib/model-routing.sh`: frontmatter 우선, `auto`/미지정 시 역할 테이블
  (판단직→opus, expert/master→sonnet, 정형 novice→haiku), `GOLEM_MODEL_ESCALATE` 승급 훅.
- ~~P1-1 턴 캡~~ → 워치독이 stream assistant 메시지 수 카운트, 초과 시 kill +
  `result=turn_cap`·`turn_cap=1` usage 필드·rc 1. `GOLEM_TURN_CAP_ENFORCE=0` 해제.
  (라이브 확인 1건은 미실시 — fake claude bats만. PERF-PLAN §10 체크박스 잔존)
- ~~P1-3 rubric verify~~ → `[ITEM-k: OK|NG]` 항목별 채점 + 코드 집계, 레거시 VERDICT 폴백,
  `GOLEM_VERIFY_RUBRIC=0` 해제.
- ~~2차 로케일 백필~~ → de/es/fr/ja/pt flowEditor 91키 완역, i18n 가드 테스트 5로케일 확장.
- ~~doctor 드리프트 감지~~ → install.sh가 `.golem-source` 마커 기록, doctor가 cksum 비교 WARN.
- runs/sessions retention 정책 — **계속 보류** (실이슈 발생 전).

## P3 — 스튜디오 확장 → ✅ 전부 완료 (2026-07-05, 엔진+클라이언트)

- ~~팀 프리셋/템플릿~~ → `templates/studio-presets/*.json`(novel-team 4인 6단계,
  market-research 3인 3단계) + `studio preset list/apply` + `GET /v1/studio-presets`
  + 생성 위저드 "시작 방식"(빈/프리셋/AI설계) 선택 UI.
- ~~design 반복 (`studio redesign`)~~ → 목표+로스터+최신 플로우 요약으로 flowsmith 재소환,
  기존 SOUL 보존 + 신규만 추가, 항상 새 플로우. 에디터 재설계 버튼(SSE 모달) + dirty 가드.
- ~~flowsmith rank/effort~~ → agent-add `[rank] [effort]` 인자 + flowsmith 계약 선택 필드
  + 에이전트 생성 모달 선택 UI (판단·검증→senior+high, 정형→novice+low 가이드).
- ~~스튜디오 삭제 UI~~ → 카드 삭제 버튼 + 확인 다이얼로그(폴더 보존 안내).

### 검수 사이클 2차 (2026-07-05, ccfff8f..a343358 대상) — 완료
HIGH 3(204 응답 파싱 실패로 삭제가 실패 표시·deleteFlow 동일 잠복 버그, 모달 ESC 회귀 13곳,
redesign dirty 덮어쓰기) + MED/LOW 7(턴 캡 grep 앵커·고속 버스트 사후 정산·rubric 에코 방어·
프리셋 중복 id 등) 전부 수정. 잔여 인지 사항: 턴 캡은 폴링(1s)+사후 정산 계약(문서화됨),
kill된 런은 비용 과소집계(대시보드 주석 감), P1-1 라이브 확인 체크박스(PERF-PLAN §10).

## 참고 (환경/컨텍스트)

- `GOLEM_EXTRA_PROJECT_ROOTS=C:/01_xuefeng` 사용자 env 설정됨 (스튜디오 경로 정책 허용 루트)
- 첫 실사용 스튜디오: `C:\01_xuefeng\08_ai\flow\xiaoshuo` (소설팀 — 4에이전트, 6단계 플로우 완주)
- 게이트웨이는 글로벌 엔진(`~/.claude/golem-garden/forge.sh`)을 실행 — lib 변경 시 `bash install.sh` 동기화 필수
