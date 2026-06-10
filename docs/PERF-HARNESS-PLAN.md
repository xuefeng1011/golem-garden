# 성능 극대화 & 모델 비종속 하네스 구성안

> 작성: 2026-06-10, 브랜치 `feat/independent-engine` (149dede 시점)
> 분석 방법: 엔진 코어(agent-runner/prompt-builder/verify/mission) + 하네스 강제층(훅/SKILL.md) + 관측성 계층(growth-log/insights) 3축 코드 감사
> v2 (2026-06-10): Fable 종료(6/22) 대비 Opus 전환 플랜, 스킬 계층 전수 감사, GitHub 하네스 트렌드 흡수 맵, physical-ai 도메인 팩 추가 — §6~§9

## 0. 핵심 진단 한 줄

**성능 = 모델 능력 × 하네스 구조.** 현재 GolemGarden은 관리 계층(세션·비용·도구권한·보호훅)은 결정론적으로 잘 강제되지만, **"지능 구간" 4곳 — 판정(verify), 분해(Director), 복구(error-recovery), 승격심사(Sage) — 이 모델 능력에 그대로 노출**되어 있다. Fable/Opus급에서는 이 구간이 잘 동작해 약점이 가려지지만, Sonnet/Haiku로 내리면 같은 하네스에서 품질이 꺾인다. 개선 방향은 하나다: **"모델이 똑똑해서 되는 것"을 "구조 때문에 되는 것"으로 옮긴다.**

## 1. 현재 상태 감사 요약

### 1.1 이미 강한 부분 (결정론 계층 — 유지)

| 영역 | 메커니즘 | 근거 |
|------|---------|------|
| 도구 권한 | rank/role → `--allowedTools`/`--disallowedTools` CLI 강제, Director 도구 오버라이드 | `lib/soul-parser.sh:112-133`, `lib/agent-runner.sh:301-336` |
| 보호 훅 | growth-log/mailbox 직접수정 PreToolUse 차단 | `.claude/hooks/guard-*.sh` |
| 자동 기록 | Stop 훅 → growth-log + 랭크 승급 + 대시보드 | `.claude/hooks/auto-growth-log.sh` |
| 테스트 판정 | bats/pytest/npm exit code 기반 (verify Stage 1) | `lib/verify.sh:63-149` |
| 타임아웃 | `AGENT_MAX_SECONDS=300` + timeout/gtimeout | `lib/agent-runner.sh:53-72` |
| 상태 파일 | mission state.json / budget state.json — escape-aware JSON 계약 | `lib/mission.sh`, `lib/budget.sh` |
| 관측 | tokens_in/out/cache, cost_usd, duration_ms JSONL 기록 | `lib/growth-log.sh:14-54` |

### 1.2 약한 고리 (모델 능력 의존 — 이번 개선 대상)

| # | 약점 | 현재 동작 | 약한 모델에서의 실패 양상 |
|---|------|----------|--------------------------|
| W1 | verify SOUL 심판 | 자유 텍스트 → 첫 줄 `PASS\|FAIL` grep, 불명확 시 SKIP | "PASSED" 등 형식 이탈 → 판정 무효화, 검증 게이트 구멍 |
| W2 | Director(Nex) 태스크 분해 | 순수 프롬프트 판단, 출력 형식 자유 | 분해 누락/중복, mission tasks 배열과 단절 |
| W3 | error-recovery 위임 | ~~`soul_match_score` 정의 부재~~ → **정정(06-10)**: 함수는 존재(soul-parser.sh), 단 키워드를 정규식으로 해석하는 취약점 | 메타문자 키워드 오탐/에러 |
| W4 | maxTurns | 프롬프트 권고 텍스트만 (CLI 플래그 부재) | 약한 모델일수록 턴 낭비 → 비용 폭증 |
| W5 | 비용캡 | `AGENT_MAX_COST_USD` **사후 경고만** | 초과를 막지 못함 |
| W6 | guard-novice | 경고만 출력 (exit 0), `GOLEM_SOUL_RANK` 미설정 시 무력 | 병렬쓰기 충돌 실제 발생 가능 |
| W7 | SOUL Memory 주입 | recall 5건 제한은 있으나 블록 크기 무제한, 효과 미측정 | 컨텍스트 낭비, 캐시 오염 |
| W8 | 리뷰/승격 형식 | `result:`/`VERDICT:` 형식 "요청"만, 파싱 실패 시 수동 | 자동 파이프라인 단절 |
| W9 | 모델 라우팅 | SOUL frontmatter `model:` 정적 지정, 랭크·역할·태스크 난이도 기반 정책 부재. `effort:` 필드 선언만 되고 미소비 | 전 태스크 단일 모델 → 비용/품질 비효율 |

### 1.3 관측 공백 (측정 안 되는 것)

- 프롬프트 캐시 히트율 (cache_read vs cache_creation 분리 안 됨)
- 세션 재개율 (`--session-id` 신규 vs `--resume` 비율)
- 미션 태스크당 턴/토큰 (복잡도 메트릭 부재)
- memory/knowledge 주입의 성과 기여 (주입 여부 플래그 없음)
- **모델별 동일 태스크 성능 비교 데이터 (모델 이식성 검증 불가)** ← 이게 "Fable 없이 같은 성능" 검증의 전제

## 2. 설계 원칙: 모델 비종속 하네스 5계명

1. **출력은 계약이다** — LLM 출력 중 기계가 소비하는 것은 전부 구조화(고정 마커 또는 JSON) + 파싱 실패 시 1회 재질의(retry-on-malformed). 자유 텍스트 grep 금지.
2. **판정의 1차 권위는 결정론** — 테스트 exit code > 체크리스트 항목별 yes/no > LLM 총평. LLM 심판은 루브릭 채점자로 격하.
3. **한계는 프롬프트가 아니라 프로세스가 강제** — 턴/비용/시간 한계를 stream 모니터링 + kill로 집행. 권고 텍스트는 보조.
4. **선택 로직은 스크립트로** — SOUL 선택, 복구 위임, 모델 라우팅은 specialty 태그 매칭 등 결정론 휴리스틱. LLM에게 "누구한테 시킬지"를 묻지 않는다.
5. **이식성은 측정으로 증명** — 골든 태스크 스위트를 모델별로 돌려 growth-log로 비교. 측정 없는 "같은 성능" 주장은 무효.

## 3. 개선 로드맵

### P0 — 정합·안전 (즉시, 작게)

| 항목 | 내용 | 대상 약점 |
|------|------|----------|
| P0-1 | **verdict 계약 도입**: verify/review/sync 심판 프롬프트에 `[VERDICT: PASS]` / `[VERDICT: FAIL reason="..."]` 고정 마커 강제. 파서는 마커만 인식, 미검출 시 "마커로만 답하라" 1회 재질의 후 FAIL 처리(SKIP 아님 — 안전 기본값) | W1, W8 |
| P0-2 | **`soul_match_score` 경화** (정정: 함수는 이미 존재): 키워드 정규식 해석 → `grep -F` 리터럴 매칭으로 교체 + 테스트 | W3 |
| P0-3 | **비용캡 사전 차단**: run 시작 전 budget state 잔액 확인 → 부족 시 거부. 사후 경고는 유지 | W5 |
| P0-4 | **guard-novice 강화**: 경고 → 차단(exit 2) 전환 + `GOLEM_SOUL_RANK` 미설정 시 "보수적 차단" 기본값. agent_run이 환경변수 주입을 보장 | W6 |

### P1 — 모델 이식성 코어

| 항목 | 내용 | 대상 약점 |
|------|------|----------|
| P1-1 | **턴 캡 집행**: stream-json의 assistant 메시지 수를 라이브 카운트, `SOUL_MAX_TURNS` 초과 시 프로세스 kill + `result=turn_cap` 기록. CLI `--max-turns` 부재를 하네스가 대체 | W4 |
| P1-2 | **Director 분해 계약**: Nex 출력 = `{"tasks":[{"task":"...","soul":"...","reason":"..."}]}` JSON 강제 → `mission_set_tasks`에 직결. 분해 품질이 모델과 무관하게 *형식상* 보장되고, 누락은 태스크 수 하한 체크로 탐지 | W2 |
| P1-3 | **루브릭 검증**: verify Stage 2를 "총평 PASS/FAIL" → "체크리스트 N항목 각각 `[ITEM-k: OK\|NG reason]`" 채점으로 전환. 약한 모델도 항목별 채점은 안정적. 종합 판정은 스크립트가 집계 | W1 |
| P1-4 | **메모리 주입 예산**: memory+knowledge 블록 합산 상한(예: 1,200자), 초과 시 최신·고태그빈도 우선 절삭. 주입 여부를 growth-log에 `memory_injected: true` 플래그로 기록 | W7 |
| P1-5 | **재질의 루프 공통화**: `_agent_retry_structured()` 헬퍼 — 구조화 출력 파싱 실패 시 동일 세션 `--resume`으로 "형식만 다시" 1회 요청. 모든 계약 소비처가 공유 | W1, W2, W8 |

### P2 — 성능·비용 극대화

| 항목 | 내용 | 대상 |
|------|------|------|
| P2-1 | **역할 기반 모델 라우팅 정책**: 판단직(director/verifier/sage) → 상위 모델, 실행직(executor류) → 중위, 정형 태스크(문서/로그/리네임) → haiku. `effort:` 필드를 실제 소비: `effort=high` → 모델 1단계 승급. SOUL frontmatter 정적 지정은 오버라이드로 유지 | W9 |
| P2-2 | **캐시 관측·최적화**: cache_read/cache_creation 분리 기록 → `forge insights`에 히트율 표시. 프롬프트 빌더의 공통 블록(전 SOUL 동일)을 바이트 단위 고정해 캐시 히트 보장 (현재 SOUL별 블록이 앞에 섞이면 캐시 무효) | 비용 |
| P2-3 | **골든 태스크 스위트 (모델 이식성 벤치)**: `tests/golden/` 에 대표 태스크 5~10개(버그수정·함수추가·문서·리뷰판정) + 결정론 채점기(테스트 통과/마커 정확도). `forge bench <model>` 로 모델별 실행 → 동일 하네스에서 모델 교체 시 성능 회귀를 수치로 확인. **"Fable 없이 같은 성능" 의 검증 장치** | 이식성 |
| P2-4 | **forge build 멀티-SOUL e2e 라이브 검증**: 남은 최대 검증 공백. mission 자율 모드 풀런 포함 | 검증 |
| P2-5 | **미션 복잡도 메트릭**: state.json에 태스크당 `turns_used`/`tokens_used` 기록 → 분해 품질·모델 적합성 분석 기반 | 관측 |

### P3 — 부채 정리

- `soul_to_omc_agent` shim 제거 (잔존 콜러 3곳: prompt-builder/error-recovery/forge-review — 전부 표시용이므로 `SOUL_ROLE` 직접 표기로 교체)
- bash/python 듀얼 growth-log 작성자 골든 테스트 (스키마 결합 암묵 → 명시)
- `personality:` 필드 처리 결정 (프롬프트 주입 or 스펙에서 제거)
- 글로벌 설치(`~/.claude/golem-garden/`) ↔ repo 동기화 자동화

## 4. Fable 활용 극대화 (지금 당장)

Fable 5가 강한 곳에 Fable을 쓰고, 결과물을 하네스에 고정시킨다:

1. **오케스트레이터 = Fable**: 메인 세션(이 레벨)에서 분해·계획·크로스리뷰 종합을 수행하고, 실행은 `forge run`으로 하위 모델 SOUL에 위임. Fable의 판단이 필요한 곳은 "계약을 설계하는 시점"이지 "매 태스크 실행"이 아니다.
2. **계약 작성에 Fable 투입**: P0-1/P1-2/P1-3의 루브릭·체크리스트·분해 템플릿을 Fable로 한 번 잘 만들어 두면, 이후 약한 모델이 그 틀 안에서 채점·분해만 하면 된다 — **Fable의 지능을 하네스에 "구워 넣는" 작업**.
3. **병렬 팬아웃**: 독립 태스크는 Fable 오케스트레이션 하에 SOUL 병렬 실행 (worktree isolation 활용). 단 Novice/Junior 병렬쓰기 금지는 P0-4로 강제 후.
4. **검증 비대칭**: 실행은 sonnet/haiku, 검증·승격심사만 상위 모델 — author≠verifier 가드(이미 있음)와 결합하면 비용 대비 품질이 가장 좋은 구조.

## 6. Fable → Opus 전환 플랜 (2026-06-22 이후)

스킬 8종 + SOUL frontmatter 전수 점검 결과 **"fable" 하드코딩 0건** — 모든 모델 참조는 opus/sonnet/haiku 별칭이고 SOUL frontmatter `model:` 필드로 중앙 관리된다. 엔진 기본값은 sonnet(`lib/agent-runner.sh:_map_model`). 따라서 전환 작업은 SOUL/스킬이 아니라 **오케스트레이터 레벨**에 집중된다.

| # | 항목 | 내용 |
|---|------|------|
| O-1 | 메인 세션 모델 | `/model opus` (Opus 4.8). 긴 출력 작업은 `/fast`(fast mode — Opus 그대로, 출력만 가속) 활용 |
| O-2 | 약점 보험 | Fable이 가려주던 약한 고리(W1~W9)는 Opus도 대부분 가려주지만, **6/22 전에 P0 4건(계약화·차단)을 끝내는 것이 전환 보험** — 이후 sonnet 폴백까지 안전해짐 |
| O-3 | 판단직 SOUL | nex/sage/sentinel/atlas는 이미 `model: opus` — 변경 불요 |
| O-4 | 비용 관리 | Opus 단가↑ → P2-1 라우팅 정책(실행직 sonnet/haiku 유지)의 우선순위 상승. `forge dashboard --cost`로 전환 전후 주간 비용 비교 |
| O-5 | 회귀 측정 | P2-3 골든 스위트를 6/22 전에 1회 돌려 Fable 기준점 기록 → 전환 후 동일 스위트로 회귀 확인 |

## 7. 스킬 계층 전수 감사 결과 (2026-06-10)

8개 SKILL.md + forge.sh verb 디스패치 대조 감사. 모델 거버넌스는 안전, **라우터 드리프트가 최대 이슈**.

| # | 발견 | 심각도 | 조치 |
|---|------|--------|------|
| S-1 | 메인 라우터에 `doctor`/`verify`/`explore`/`insights` 4개 verb 라우팅 규칙 누락 (forge.sh에는 구현됨) | 🔴 | 라우터 SKILL.md 키워드 표에 추가 ("진단/헬스체크"→doctor, "검증"→verify, "탐색"→explore, "성과/분석"→insights) |
| S-2 | forge-review에 SOUL 가시성 배너(>>/<<) 미기재 + 3단계 복구 없음(1회 재시도만) | 🟡 | 배너 표준 적용 + 복구 프로토콜 통일 |
| S-3 | forge-handover Phase C(4 SOUL 병렬) 부분 실패 처리 미정의 | 🔴 | 1명 실패 시 해당 섹션 빈 상태로 계속 + 사용자 보고 규칙 명시 |
| S-4 | forge-team ↔ forge-mission 가시성 배너 95% 복붙 | 🟢 | 라우터에 "표준 배너" 섹션 1곳으로 통합, 서브스킬은 참조 |
| S-5 | 도메인 팩 제작 절차 미문서화 (`lib/domain-pack.sh`만 존재) | 🟡 | physical-ai 팩 추가(§9)로 절차 검증됨 — 그 절차를 스킬 문서화 |
| S-6 | forge-init의 세션 생성 여부 불명 (team/mission은 명시) | 🟡 | forge-init Step에 세션 정책 명시 |

## 8. GitHub 인기 하네스 흡수 맵 (2025H2~2026 트렌드 조사)

조사 대상 18개 프로젝트/패턴 중 흡수 가치 Top 5를 로드맵에 직결. 공통 교훈: **"하네스가 점수의 절반"** (Terminal-Bench 인사이트 — 같은 모델도 하네스에 따라 5~8점 차이), 본 문서의 §2 5계명과 정확히 일치.

| 순위 | 출처 (인기) | 흡수 메커니즘 | 로드맵 반영 |
|------|------------|--------------|------------|
| 1 | LLM-as-Judge 수렴 패턴 | 판정 = `--output-format json` + 루브릭 JSON 스키마 + 결정론 사전검증 + **haiku→sonnet 판정 캐스케이드**, `lib/judge-contract.sh`로 공통화 | **P0-1 격상** — 마커 방식 대신 judge-contract 모듈로 구현, P1-3/P1-5와 통합 |
| 2 | Ralph (20k★) + OpenHands (70k★) | 스토리별 `passes` 불리언 + `<promise>COMPLETE</promise>` 센티널 종료 + append-only progress 인계 + 반복 상한, **스턱 디텍터**(최근 N반복 diff 해시/명령 시그니처 동일 → 에스컬레이션) | **P1-6 신설** — mission 루프 계약. error-recovery 3단계와 연결 |
| 3 | Terminal-Bench (사실상 표준) + mini-SWE-agent | `tests/eval/{task}/instruction.md + verify.sh` 태스크 규격 + `forge eval` 배치 러너 → growth-log 점수 기록 | **P2-3 구체화** — 골든 스위트의 파일 규격으로 채택 |
| 4 | Aider (45k★) + RouteLLM | **Architect/Editor 2패스**(설계 opus → 편집 haiku/sonnet) + 정적 라우팅 테이블(태스크 유형×랭크) + 실패 시 모델 승급 재시도 | **P2-1 구체화** — "정적 if문 라우팅이 70%의 이득" (비용 40%+ 절감 보고) |
| 5 | GitHub spec-kit (111k★) | 미션 스펙 단계에 `/clarify`(커버리지 질문 게이트) + `/analyze`(spec-plan-tasks 교차 일관성 검사) + `constitution.md`(프로젝트 헌법, 캐시 프리픽스 주입) | **P1-7 신설** — forge mission 인터뷰 배치에 clarify, 실행 전 analyze 게이트 |

**차순위 (P2~P3 후보):**
- Letta/MemGPT — soul-memory를 "크기 예산 코어 블록(상시 주입) + grep 아카이브" 2계층화 + Stop 훅 회고를 "dream 패스"(세션 후 메모리 압축·승격)로 확장 → P1-4와 결합
- BMAD-METHOD — Director→SOUL 인계를 "자기완결 스토리 파일"(배경/제약/수락기준 포함 mailbox 규격)로 격상
- AGENTS.md 표준 (60k+ 저장소, Linux Foundation) — forge-init이 AGENTS.md 생성/소비. 단 "사실·명령 중심, 짧게" (LLM 생성 장황 컨텍스트는 성능 해침 — 통제 연구 결과)
- claude-flow 신뢰 점수 (`0.4×성공률+...`) — rank-system에 이식해 Director의 SOUL 선택 가중치로
- claude-squad — 세션 pause/resume 시맨틱을 session.sh+worktree에 추가
- vibe-kanban — 미션 태스크에 attempt 배열(soul/결과/비용) 1급 객체화

### 8.1 채택/보류 판정 (비대화 방지 — 2026-06-10 추가)

하네스 무게는 두 종류다: **코드 무게**(스크립트·훅 — 한 번 지불, 결정론)와 **컨텍스트 무게**(매 호출마다 지불하는 프롬프트 텍스트 — 모델 의존). 근거: AGENTS.md 통제 연구(장황한 LLM 생성 컨텍스트는 8개 중 5개 설정에서 성능 악화), mini-SWE-agent(코어 100줄로 SWE-bench 74%). **채택 기준: 추가물은 ① 프롬프트 텍스트를 줄이거나 ② 결정론 게이트를 더하거나 ③ 소비되는 측정을 더해야 한다. 셋 다 아니면 거부.**

| 항목 | 판정 | 이유 |
|------|------|------|
| Top5-1 judge-contract, Top5-3 forge eval, Top5-4 라우팅 | **채택** | 지능→구조 이동. 코드는 늘지만 호출당 컨텍스트·모델 의존은 줄어듦 |
| Top5-2 Ralph 계약+스턱디텍터 | **부분 채택** | passes 불리언·센티널·스턱디텍터만. progress 인계 파일은 growth-log와 중복 — 생략 |
| Top5-5 spec-kit clarify/analyze | **절삭** | mission에 이미 인터뷰 배치+검증 게이트 존재. 게이트 2개 추가는 의식(ceremony) — analyze는 기존 verify 루브릭의 체크 항목 1줄로 흡수 |
| Letta 2계층 메모리+dream 패스 | **보류** | memory 주입 효과 자체가 미측정(§1.3). eval로 효과 측정 후 결정 |
| claude-flow 신뢰 점수 | **거부** | rank+success_rate가 이미 같은 신호. 점수 체계 중복 = 비대화 |
| BMAD 스토리 파일 | **채택(소형)** | mailbox 메시지 형식 규격화 — 텍스트 1템플릿, 무게 거의 0 |
| pause/resume, attempt 배열 | **보류** | nice-to-have. 코어 루프 완성 후 |
| 게이미피케이션 확장(chemistry/achievement/skill-tree/dna 추가 기능) | **동결** | 기능 ROI 미측정 상태에서 유지보수 무게만 증가 — 신규 추가 금지 |
| Agent-Reach식 doctor 보강 | **채택(소형)** | 기존 `forge doctor`(lib/doctor.sh)에 채널식 `check()→(status,msg)` 계약 + tier 분류 + 수리 제안 형식만 이식 |
| Agent-Reach식 progressive disclosure | **채택** | 라우터 SKILL.md 비대 해소(S-4와 결합) — 상세를 references/로 분리해 **컨텍스트 무게 감소** |
| **프롬프트 다이어트 (신규 D-1)** | **채택** | 전역 CLAUDE.md의 OMC 잔재 제거(디커플 완료에 맞춰), rules 7종 중 중복·미적용 항목 정리, "사실·명령 중심 짧게" 원칙 적용 |

## 9. physical-ai 도메인 팩 (완료 — 2026-06-10)

IoT·AIoT·Go·로보틱스 전문 SOUL 4종을 `domain-packs/physical-ai/`로 추가, repo와 글로벌(`~/.claude/golem-garden/`) 양쪽에 설치 완료.

| SOUL | 역할 | 모델 | specialty 핵심 |
|------|------|------|---------------|
| Ember | embedded-developer | sonnet | esp32/stm32, freertos/zephyr, mqtt, ble, 저전력 |
| Neura | edge-ai-engineer | sonnet | tinyml, tflite-micro, onnx, 양자화, 엣지 추론 |
| Gopher | backend-developer (Go) | sonnet | golang 동시성, grpc, mqtt 브로커, 시계열, 플릿 API |
| Atlas | robotics-engineer | opus | ros2, slam, 센서퓨전, 제어루프, 안전 (effort: high) |

Atlas만 opus인 이유: 제어·안전은 판단직(§4-4 검증 비대칭 원칙). 보드에 forge 실행 모드 매핑 포함(`forge-board-physical-ai.md`).

## 10. 수용 기준 (이 계획의 완료 판정)

- [x] P0 4건: bats 음성 테스트 포함 통과 — 2026-06-10 완료, 신규 테스트 21건 (187/187)
  - P0-1 `[VERDICT:]` 마커 계약 + 재질의 1회 + 안전 기본값 FAIL (verify.sh)
  - P0-2 `soul_match_score` grep -F 경화 (soul-parser.sh)
  - P0-3 `_agent_budget_preflight` 예산 사전 차단, `GOLEM_BUDGET_OVERRIDE=1` 우회 (agent-runner.sh)
  - P0-4 guard-novice 차단 전환(exit 2) + **추가 발견 수정**: agent_run이 SOUL env를 child에 미주입해 가드가 사문화 → `env GOLEM_SOUL_NAME/RANK` 주입 추가. zen 라이브 스모크 통과
  - 글로벌 엔진(~/.claude/golem-garden/lib/) 동기화 완료
- [ ] P1-1: 턴 캡 초과 시 kill + growth-log `turn_cap` 기록 라이브 확인
- [x] P2-3: `forge eval` 골든 스위트 — 2026-06-10 완료. `lib/eval.sh` + `tests/eval/` 5종(bugfix/func/jsonl/doc/verdict-format) + `AGENT_MODEL_OVERRIDE` + bats 11건 (198/198). growth-log 오염 방지(GROWTH_DIR 우회) 포함
- [x] P2-4: `forge build` 멀티-SOUL e2e 라이브 완주 — 2026-06-11. 세션→예산→Nex(opus) 분배→mailbox→Ryn∥Zen 병렬→복구 프로토콜(타임아웃 1회, 분할 재시도 성공)→세션 종료. **e2e가 잡은 실결함 3건 수정**: ① 비-UUID session_id 즉시 fail(UUID 가드+폴백 추가) ② forge-board "자동 태스크 누적" 문서 거짓(growth_log_append→board_update_timestamp 배선+문서 정정) ③ 타임아웃 가드 라이브 작동 확인(범위 과대 태스크 분할 필요 — Ryn memory에 학습 기록). 산출물: eval v2 hard 태스크 2종(refactor-dedup, spec-edgecase — 호스트 음성 검증 통과) + Zen의 v1 채점기 감사 보고
- [x] O-5: Fable 기준점 기록 — 2026-06-10 라이브 완료. **claude-fable-5 5/5, sonnet 5/5, haiku 5/5** (`.golem/eval/results.jsonl`). 발견: v1 스위트는 천장 효과(전 모델 만점) — 회귀 감지용으로는 유효하나 모델 변별력은 없음. **v2 과제: 변별력 있는 hard 태스크 추가** (멀티스텝 리팩터링, 모호 명세 해석, 대형 컨텍스트). 부수 확인: haiku도 [VERDICT:] 마커 계약을 준수 → P0-1 계약이 약한 모델에서 실효적
- [x] S-1: 메인 라우터에 doctor/verify/explore/insights 라우팅 추가 — 2026-06-10 완료 (repo + 설치본 동기화)
- [x] §9: physical-ai 팩 4 SOUL repo+글로벌 설치 (2026-06-10 완료)
- [x] 회귀 0: bats 187/187 (기존 166 + P0 신규 21) — 2026-06-10
