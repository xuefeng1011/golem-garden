# GolemGarden Web UI — 제품 플랜 v2

> v1 (2026-04): MVP 계획 — Phase 1~3 완료로 역할 종료.
> v2 (2026-06-11): 현황 감사 반영 전면 개정. 목표 전환 — "동작하는 데모" → **판매급(product-grade) 대시보드**.

## 1. 현재 상태 (v1 플랜 대비 실제 구현)

| v1 계획 | 실제 상태 |
|---------|----------|
| Phase 1 Gateway 스켈레톤 | ✅ 완료+초과 — FastAPI, 엔드포인트 25+, pytest 187 |
| Phase 2 Claude 브리지+SSE | ✅ 완료 — runs/SSE/하트비트/256KB 캡/워치독 |
| Phase 3 Hermes 포크 연결 | ✅ 완료+초과 — "5개 파일 수정" 범위를 넘어 13개 뷰의 풀 앱으로 성장 (web/ui → `web/client`) |
| Phase 4 후보 | rank 배지 ✅ / SQLite 영속화 ✅ (sessions.db v1+마이그레이션 프레임) / circuit breaker·크로스리뷰·SOUL 생성기 미구현 |

**스택**: Vue 3.5 + Pinia 3 + Naive UI 2.44 + vue-i18n(8개 언어) + Vite 8 / FastAPI + uv.

**감사 결론 (2026-06-11)**: 아키텍처·컴포넌트 구조는 건강("기술 데모→베타" 단계, 판매 준비도 ~70%). 격차는 기능이 아니라 **마감 품질**이다:
- 디자인 토큰 불일치 (theme.ts primary `#2d7a57` vs variables.scss `--accent-primary #333`)
- 상태 3종(빈/로딩/에러) 비표준 — 텍스트만 있거나 부재
- **게이트웨이가 이미 노출하는 가치 데이터를 UI가 안 씀**: chemistry, daily cost, rank_progress, skill-tree, mailbox
- forge 명령 인자 입력 UI 부재, 모바일 UX 약함, 테스트 0%

## 2. 제품 비전 — "판매급"의 정의

전문가가 신뢰하고 비전문가가 즐길 수 있는 **AI 에이전트 팀 운영 대시보드**:

1. **First-run이 비어 보이지 않는다** — 모든 화면에 디자인된 빈 상태(아이콘+설명+다음 행동 버튼).
2. **기다림이 보인다** — 스피너 대신 스켈레톤, 스트리밍은 진행 컨텍스트 표시.
3. **데이터가 이야기한다** — 비용 추세, 랭크 진행도, 팀 케미를 숫자가 아니라 시각으로.
4. **일관된 언어** — 단일 색·간격·그림자 토큰, 라이트/다크 모두 의도된 대비.
5. **실패가 친절하다** — 에러 유형별 메시지 + 복구 행동 제시.

## 3. Phase 5 — 판매급 폴리시 (이번 구현)

병렬 3개 수직 영역, 파일 소유권 분리:

### P5-A 디자인 시스템 + 공용 프리미티브 (소유: styles/*, components/common/*)
- 토큰 정합: primary 일관화(light `#2d7a57` / dark 보색 녹색), 다크 대비 재조정, shadow/easing 토큰화
- 신규 공용 컴포넌트: `EmptyState`, `SkeletonCard`, `RankProgress`, `MiniBarChart`(의존성 없는 SVG — 외부 차트 라이브러리 도입 금지)
- 각 컴포넌트 vitest 단위 테스트

### P5-B Overview·Souls 수직 (소유: views/Overview·Souls, components/hermes/overview·souls)
- StatCards: 스켈레톤 + 아이콘 + 시각 위계
- SoulCard/DetailModal: 랭크 진행도(`rank_progress` API — 이미 노출됨), hover 폴리시, 빈 상태 적용
- RecentActivity 가독성 개선

### P5-C 가치 데이터 노출 수직 (소유: views/Usage·Team, api/hermes/budget·chemistry)
- UsageView 재구축: `GET /budget` → 총비용/SOUL별/일별 차트(MiniBarChart) + 예산 경고선
- 팀 케미 시각화: `GET /chemistry` → pair 카드/히트맵 (TeamView 통합)
- 활용 API는 전부 기구현 — gateway 변경 없음 (Top3 미사용 API 소진)

**수용 기준**: `npm run build`(vue-tsc 포함) 통과 / `vitest run` 통과(신규 컴포넌트 테스트 포함) / gateway pytest 187 무변동 / 라이트·다크 양쪽 토큰 일관.

## 4. Phase 6 — 진행 현황 (2026-06-12 갱신)

1. ✅ Forge 명령 인자 입력 폼 (`e3140c7` — commandSchema + 필수 검증)
2. ◐ Chat: ~~가상 스크롤~~ → **윈도잉으로 대체 구현**(`e55b9ed` 마지막 80개+더보기 — 의존성 0 원칙). **보류**: 파일 업로드 백엔드(게이트웨이 엔드포인트 필요), 모바일 drawer+제스처
3. ✅ 에러 유형 체계화 (`cffd990` — ApiError 5종 + 뷰별 유형 메시지 + 게이트웨이 힌트)
4. ✅ Skill-tree·Mailbox 노출 (`cffd990` — SoulDetail 전문화 섹션, Activity 메일박스 토글)
5. ◐ A11y: 채팅 영역 aria-label/aria-hidden 1차 완료(`e55b9ed`). **보류**: 전 화면 WCAG AA 대비 검사, 키보드 내비 체계화
6. ✅ Circuit breaker UI (`e55b9ed` — BudgetGuardBanner 80%/100% 2단계, 엔진 P0-3 정합)

### Phase 5/6 동안 함께 들어온 것 (업스트림 체리픽)
펜스 복구·탭 제목·완료 알림·메시지 복사(`4987a08`), 큐·리사이즈·일괄삭제·export·아웃라인·thinking 표시(`d34f6b9`), per-run 모델 오버라이드(`6a53b27`)

### Phase 7 후보 (정정 2026-07-03 — 상당수는 다른 트랙에서 이미 구현됨)
- ✅ 세션 트리 UI — OBSERVABILITY Phase C `/hermes/canvas` 세션 트리 뷰로 완료 (`9992d98`)
- ◐ forge mission 시각화 — Canvas 미션 DAG 뷰 존재(`9992d98`) + `POST /missions/{id}/run` 실행 API(`6a2b721`). 칸반 형태 보드는 미착수
- 미착수 잔여: 파일 업로드 백엔드, 모바일 제스처, 전 화면 A11y 감사

### 계획 외 완료된 대형 트랙 (이 문서 범위 밖에서 진행)
- **Flow Engine + 시각 워크플로우 편집기** (`7c44e0f`~`f928058` 다수): DAG 정의·실행·승인 게이트·재시도, 드래그 편집기, 저장/로드/삭제, `{{단계}}` 데이터 참조, 실행 진행 폴링(단건 GET), self-heal
- **관측 콘솔 A/B/C** — OBSERVABILITY_PLAN.md 참조
- **forge mission run 결정론 루프** — PERF-HARNESS-PLAN P1-6 참조

## 5. 원칙 (v1 계승 + 갱신)

1. Gateway는 얇게 — Claude Code가 주인공 (유지)
2. SOUL.md는 파일 그대로 (유지)
3. 로컬 1인용, 127.0.0.1 (유지)
4. ~~Hermes 수정 5개 파일 제한~~ → 폐기: 자체 앱으로 전환 완료. 대신 **외부 의존성 추가 금지**(차트 등은 자체 SVG)
5. 상태 3종(빈/로딩/에러) 없는 화면은 머지 금지 (신규 원칙)

## 6. 리스크

| 리스크 | 대응 |
|---|---|
| i18n 8개 언어 키 누락 | en+ko만 필수, 나머지는 en 폴백 (messages.ts 병합 구조 활용) |
| 차트 직접 구현 품질 | MiniBarChart 범위 고정(바+임계선만), 복잡 시각화는 Phase 6 |
| 테스트 0%에서 출발 | Phase 5 신규 컴포넌트부터 테스트 의무화, 기존 소급은 점진 |
| 다크모드 회귀 | 토큰 단일화 후 양 모드 수동 QA 체크리스트 |

## 7. 실행/검증 명령

```powershell
# client
cd web\client ; npm run dev          # 개발 (5173)
npm run build                         # vue-tsc + vite build (게이트)
npx vitest run                        # 단위 테스트

# gateway
cd web\gateway ; uv run python -m golem_gateway.main   # 127.0.0.1:8642
uv run pytest                         # 187 케이스
```
