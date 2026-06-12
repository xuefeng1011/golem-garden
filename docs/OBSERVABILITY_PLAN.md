# Agent Observability & Governance 콘솔 — 심층 분석 + 설계 플랜

> 2026-06-12. 사용자 요구: Canvas·Flow·Knowledge/MCP/Reasoning Trace·Replay·Harness Dashboard.
> 결정: Vue Flow 라이브러리 허용 / Flow Engine은 다음 트랙(엔진 P1과 통합 설계) / **성능 병목 0 조건**.

## 1. 심층 성능 분석 결론

**판정: 병목 없이 구현 가능 — 단, 아래 가드레일 G1~G10 준수 조건.** 식별된 병목 후보 7개는 전부 설계 단계에서 회피 가능하며, 회피하지 않으면 실제로 문제가 된다 (특히 G1·G2).

### 1.1 실측 수치 (2026-06-12)

| 항목 | 실측 | 함의 |
|------|------|------|
| stream-json 최소 런(PONG) | 8KB / 11라인 | 고정 오버헤드 ~6KB (init+result) |
| 대형 런(tokens_out 12.6k) 추정 | 100~400KB | 도구 IO 포함. 256KB 캡 전례와 일치 |
| 일일 운영 추정 (20런) | 1~2MB/일 | **보존 정책 필수** — 기본 14일 또는 200런 롤링 |
| 현존 .golem 전체 | ~125KB, sessions.db 48KB | 현재는 매우 가벼움 |
| 클라 폴링 부하 | 초당 0.01~0.1 req | LOW — 여유 큼 |
| activity API | 요청당 JSONL 5~7개 재파싱 100~150ms | 트레이스 API에 같은 패턴 금지 |
| bash 스트림 파싱 | 파일 4~5회 선형 스캔 (1MB 기준 ~750ms 누적) | 보존 시 스캔 수 줄여야 |
| sessions.db | WAL 이미 활성, 배치 insert 존재 | 양호 — 패턴 상속 |

### 1.2 Vue Flow 성능 검증 (도입 가)

| 항목 | 수치 |
|------|------|
| 번들 | core 51KB gzip (+bg/controls/minimap 합계 71.5KB) — **lazy route로 격리** (라우터가 이미 전 라우트 dynamic import) |
| 체감 저하 시작 | ~200노드 (최적화 없이) / 컬링·메모이즈 적용 시 ~1,000노드 실용 |
| 컬링 | `onlyRenderVisibleElements` 공식 지원 (기본 false, 팬 중 mount 스파이크 주의) |
| 레이아웃 | dagre 25KB gzip (정적 사전계산) — elkjs(433KB)는 비도입 |
| 유지보수 | v1.48.2 (2026-01), 월 1회 릴리스, 주간 35만 DL, Vue ^3.3 호환. 리스크: 단일 메인테이너 |
| 우리 규모 | 에이전트 흐름도 수십~수백 노드 → **안전 마진 충분** |

## 2. 설계 가드레일 (G1~G10 — 위반 시 병목 실재)

| # | 가드레일 | 근거 |
|---|---------|------|
| G1 | **라인당 디스크 append 금지** — gateway는 메모리 버퍼(상한 512KB) → run 종료 시 일괄 쓰기. bash는 이미 받은 stream 파일을 `mv`로 보존(추가 I/O 0) | 라인당 fsync 시 드레인 50~90% 저하 |
| G2 | **bash 추가 스캔 0회 원칙** — 보존 = `rm` 대신 `mv "$stream_file" "$GOLEM_DIR/runs/<run_id>.jsonl"` 한 줄. 파생 메타는 이미 파싱한 값(_AR_*)으로 1줄 사이드카(.meta.json) | 현 4~5패스에 추가 패스 금지 |
| G3 | **트레이스 API는 mtime 캐시 상속** — activity.py `_cached_load_growth_log` 패턴. 요청당 풀 재파싱 금지 + 페이지네이션(기본 limit 200 이벤트) | 재파싱 100~150ms 누적 방지 |
| G4 | **보존 정책 내장** — `.golem/runs/` 기본 14일/200런 롤링 (run 종료 훅에서 초과분 삭제). 환경변수 GOLEM_RUNS_KEEP | 1~2MB/일 누적 |
| G5 | **시크릿 마스킹** — 보존 직전 정규식 1패스 (sk-..., ANTHROPIC_API_KEY=, ghp_... 등) → `***`. bash/gateway 동일 규칙 | 트랜스크립트 박제 위험 |
| G6 | **이중 작성자 골든 테스트** — bash/gateway가 같은 runs 스키마 — 처음부터 양쪽 산출물 비교 테스트 (growth-log 부채 재발 방지) | 기존 부채 패턴 |
| G7 | **Canvas: shallowRef + 노드 data에 id만** — 트랜스크립트 등 큰 객체를 노드에 넣지 않음. 클릭 시 트레이스 API lazy fetch | Vue 깊은 반응성이 최대 병목 |
| G8 | **Canvas: 300노드 초과 시 컬링 on + 접기(한 번에 ≤50개 펼침, rAF 배치)** — 노드 컴포넌트는 plain div (NCard 금지) | unhide 100ms 블록 보고 |
| G9 | **레이아웃 dagre 사전계산, 드래그 이벤트에 레이아웃 computed 금지** + vite manualChunks로 vue-flow 청크 분리 | 드래그 중 재배치 = 급락 |
| G10 | **대시보드 폴링 통합** — 신규 폴링 추가 대신 단일 `GET /v1/projects/{id}/console` 집계 엔드포인트(런 레지스트리+budget+counts) 10초 1회. 화면별 개별 폴링 금지 | 폴링 분산 방지 |

## 3. 데이터 기반 — Phase A: 런 트래젝토리 영속화

**원천 단일화**: 모든 관측 기능은 `.golem/runs/`의 파생 뷰.

```
.golem/runs/
  <run_id>.jsonl       # claude stream-json 원본 (마스킹 적용)
  <run_id>.meta.json   # 1줄 사이드카: {run_id, session_id, soul, model, ts_start,
                       #   duration_ms, tokens_in/out/cache, cost_usd, result,
                       #   tool_counts: {Read: n, Bash: n, ...}, source: bash|gateway}
```

- **bash**: agent_run에서 `rm` → 마스킹 1패스 + `mv` (G2). meta는 기파싱 값 재사용.
- **gateway**: `_drain_stdout`에서 라인을 메모리 버퍼에 동시 적재(G1) → run 종료 시 일괄 기록. tool_counts는 기존 tool_log에서.
- **API**: `GET /v1/projects/{id}/runs`(meta 목록, 페이지네이션) / `GET /v1/runs/{run_id}/trace?offset&limit`(이벤트 페이지) — G3 캐시.
- **테스트**: bash↔gateway 스키마 골든(G6), 마스킹 음성 케이스, 롤링 삭제.

## 4. Phase B: 파생 뷰 5종 (저비용·고가치 순)

1. **Harness Dashboard** — `/console` 집계 API(G10): 실행중/대기중/실패 런(레지스트리), 성공률·재시도·평균시간·비용(기존 growth-log/budget 재사용). 화면: OverviewView 확장 또는 신규 ConsoleView.
2. **Agent Replay** — 런 선택 → 트레이스 이벤트 타임라인(시각·이벤트·내용), 재생 커서(클라 측 타이머 — 서버 부하 0).
3. **Tool/MCP Trace** — 같은 트레이스의 tool.started/completed 쌍을 표로: 도구·입력 요약·결과·시간. `mcp__` 프리픽스 필터 탭.
4. **Reasoning Trace** — thinking 블록 + 도구 호출 교차 시퀀스 (이미 message.thinking 파이프라인 존재).
5. **Knowledge Trace** — Read/Grep 호출의 file_path 집계(참조 문서) + soul-memory/knowledge-sync 주입 기록 결합. "잘못된 참조 탐지"는 후속.

## 5. Phase C: Canvas (Vue Flow)

- 신규 lazy 라우트 `/hermes/canvas` (vue-flow 청크 분리, G9).
- 뷰 3종(같은 캔버스의 데이터 소스 전환): ① 실행 흐름(런들의 SOUL 노드 + 메일박스 from→to 엣지) ② 미션 DAG(state.json tasks) ③ 세션 트리(parentId).
- 노드 클릭 → 우측 패널에 Replay/Trace (Phase B 재사용).
- dagre 상하 레이아웃(주신 예시 Planner↓Architect↓... 형태), G7·G8 준수.

## 6. 범위 제외 (이번 트랙)

- **Flow Engine** (조건분기·병렬·승인·재시도 정의) → 엔진 P1(Nex 분해 JSON 계약, Ralph 루프)과 통합 설계하는 별도 트랙. Canvas의 읽기 전용 흐름도가 먼저 깔리면 Flow 에디터는 그 위에 얹는 구조가 됨.
- 멀티유저/권한, 트레이스 전문 검색(전문 인덱스), elkjs 실시간 레이아웃.

## 7. 수용 기준

- [x] Phase A — 2026-06-12 완료 (`e51401c`·`7dec825`·`3f8e189`): bash·gateway 양 경로 runs/ 보존 라이브 확인, 골든 스키마(G6)·마스킹(G5)·롤링(G4) 테스트 통과, bats 213/pytest 224, 드레인 회귀 없음(2.18s). **보너스 발견·수정**: SSE 종료/disconnect 시 drain cancel로 터미널 부기(growth-log 포함)가 통째로 스킵되던 잠복 버그 — cancel-safety + 경합 회귀 테스트. `.golem/runs/`는 gitignore(런타임 산출물)
- [ ] Phase B: 5개 뷰 — 트레이스 API p50 < 100ms(캐시 히트), 페이지네이션 동작
- [ ] Phase C: 300노드 합성 데이터에서 팬/줌 60fps 체감(수동 QA), vue-flow 청크가 메인 번들과 분리
- [ ] 전 게이트: build + vitest + pytest + bats 그린
