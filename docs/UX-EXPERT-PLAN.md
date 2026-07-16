# UX-EXPERT-PLAN — 3축 개선 로드맵 (A 편의성 / B 전문가 사고 / C 자동 플랜)

> Nex(Director) 심층 분석, 2026-07-12. P0 5건은 같은 날 구현 완료 — 본 문서의 정본 가치는 P1/P2 로드맵.

---

# GolemGarden 개선 플랜 — 3축 심층 분석 (Nex, 2026-07-12)

## 1. 현황 진단 — 기능 인벤토리 대비 갭 맵

엔진은 이미 "부품"을 거의 다 갖고 있다. **없는 것은 부품이 아니라 부품을 잇는 앞단(트리아지)과 밑단(환경 계약)이다.**

| 능력 | 현재 구현 | A(편의성) 관점 갭 | B(전문가 사고) 관점 갭 | C(자동 플랜) 관점 갭 |
|---|---|---|---|---|
| 명령 진입 | 스킬 라우터 퍼지 매칭 + 오타 처리 + 다음 작업 안내 (SKILL.md) | 명령 체계 자체는 우수. 그러나 **quick/build/mission 중 무엇을 쓸지는 여전히 사용자 판단** | — | **트리아지 부재가 핵심 갭** — 라우터는 "키워드→모드" 매핑만 하고 복잡도는 안 본다 |
| 환경 진단 | doctor.sh (CLI/lib/권한/드리프트 체크) | **진단 결과가 SOUL에게 전달 안 됨** — 호스트가 TMPDIR/uv 노트를 매 프롬프트 수동 주입 (실측 마찰 #2, #3) | SOUL이 환경 함정을 몰라 턴을 낭비 → 얕은 실패 | — |
| bats 실행 | run.sh Windows TMPDIR 워크어라운드 | **비ASCII 필터 누락 확인** — `run.sh:27`의 `^[A-Za-z]:` 정규식이 `C:\Users\최설봉\...` (한글 포함)을 그대로 통과시킴. line 38 주석의 "ASCII-safe fallback"은 Windows 경로가 아예 없을 때만 작동 | | |
| 턴/시간 가드 | agent-runner P1-1 워치독 (라이브 카운트 + 사후 정산) | **캡이 태스크 규모와 무관한 상수** (novice 15/junior 25) → 멀티파일 태스크 4회 중도 사살, 수동 해제로 우회 (마찰 #1) | 캡 사살은 "깊게 생각할수록 죽는" 역인센티브 | 플랜 모드가 스텝별 규모를 알면 캡을 산정할 수 있는데 그 연결이 없음 |
| 완료 판정 | `<usage> result=` (success/fail/timeout/turn_cap), mission의 `<promise>COMPLETE</promise>` | **일반 `forge run`에는 SOUL측 완료 계약이 없음** → 마커 없이 죽으면 부분 산출물을 호스트가 수동 판정 (마찰 #4). growth log의 files/tests는 항상 0 | 자가검증 없이 "다 했습니다"로 끝나는 얕은 종료 허용 | verify 게이트가 mission 경로에만 있음 |
| 프롬프트 조립 | prompt-builder 캐시 최적화 (정적/휘발 분리), 랭크 제약, SOUL 메모리 주입 | | **랭크 제약이 "권한" 서술뿐, "사고 절차" 강제가 없음.** 셀프 크리틱/가정 명시/계획 선행 장치 전무 | Director 프롬프트의 출력 형식이 v0 줄 단위 — FLOW_CONTRACT v1 JSON과 **이중 계약** |
| 분해 계약 | FLOW_CONTRACT v1 (deps DAG/retry/approval/on_fail) + flow-dag 병렬 웨이브 + mission set-tasks-json | | | **부품 완비, 자동 발동 경로 부재** — 사용자가 mission을 명시해야만 작동. 태스크 분해도 패키지 단위까지만 (마찰 #5) |
| 자율 루프 | mission-loop (사이클/재시도 상한, 스턱 디텍터, 예산 센티널) | 사용자가 mission 개념을 알아야 씀 | verify.sh rubric 채점 존재 — 단 **사후 채점만**, 착수 전 기준 합의 없음 | 트리아지가 complex 판정 시 자동 진입해야 할 종착지 |
| 모델/effort | model-routing 정적 테이블 + GOLEM_MODEL_ESCALATE | | **effort 배선 미완** (2026-06-11 보류 항목) — frontmatter effort가 CLI까지 전달 안 됨 | |

**강점 (유지)**: 캐시 최적화 프롬프트 구조, 결정론 우선 철학(라우팅/루프/채점을 코드로 강제), verify author≠verifier 가드, 스킬 라우터의 다음 작업 안내 UX.

---

## 2. 개선안

### A축 — 사용자 편의성

#### A-1. 환경 계약 자동 주입 (env-probe) — **이번 플랜의 A축 핵심**

- **문제**: bats TMPDIR, uv 부재, venv python 경로 같은 환경 사실을 호스트가 매 프롬프트에 수동 주입한다. SOUL은 모르면 턴을 태우며 스스로 발견하거나 조용히 전멸한다 (마찰 #2, #3).
- **설계**: `lib/env-probe.sh` 신설. doctor.sh의 체크 로직을 재사용하되 산출을 사람용 리포트가 아닌 **머신 주입용 계약 파일** `.golem/env.md`로 쓴다. 내용: 검증된 테스트 명령 3종(bats: `TMPDIR=C:/tmp/golem-bats bash tests/bats/run.sh`, pytest: 해결된 python 경로, vitest), 사용 가능/불가 도구(uv 유무 → 폴백 명령), OS 함정 노트(taskkill //T 등). `prompt-builder.sh`의 `prompt_build_static`이 이 파일 존재 시 **준정적 블록**으로 주입 (skill-tree 블록과 같은 위치 — env.md는 환경 변경 시에만 바뀌므로 캐시 계약 유지). 갱신 트리거: `forge doctor` 실행 시 + env.md 부재 시 forge run이 1회 자동 프로브.
- **왜 지금 이 설계인가**: doctor는 이미 사실을 안다. 문제는 전달 채널이었고, prompt-builder에는 이미 준정적 블록 슬롯(skill-tree)이 있어 캐시를 깨지 않고 꽂을 자리가 존재한다.
- **난이도**: M · **기대 효과**: 환경 관련 턴 낭비/전멸 제거, 호스트 수동 주입 0회
- **성공 기준**: forge build 1사이클에서 (1) 호스트의 환경 노트 주입 0회, (2) SOUL의 테스트 첫 실행 성공률 — 환경 원인 실패 0건 (growth log fail 사유로 측정)

#### A-2. run.sh 비ASCII 경로 필터 (즉시 수정)

- **문제**: `tests/bats/run.sh:27`이 `^[A-Za-z]:`만 검사 → 한글 username TEMP(`C:\Users\최설봉\AppData\...`)를 유효 경로로 통과시켜 bats가 조용히 전멸. line 38의 ASCII 폴백은 도달 불가 코드다.
- **설계**: 후보 검사에 비ASCII 거부 추가 — `[[ "$candidate" =~ ^[A-Za-z]: ]] && [[ ! "$candidate" =~ [^[:ascii:]] ]]` 일 때만 채택, 아니면 `C:/tmp/golem-bats` 폴백. `test_portability.bats`에 한글 경로 시나리오 회귀 추가.
- **난이도**: S · **성공 기준**: `TEMP='C:\Users\최설봉\AppData\Local\Temp' bash run.sh` 가 C:/tmp 폴백을 선택하는 bats 테스트 통과

#### A-3. 검증 명령 폴백 체인

- **문제**: CLAUDE.md의 `uv run pytest` 류가 uv 미설치 환경에서 그대로 실패 (마찰 #3).
- **설계**: `verify.sh::_verify_run_tests`의 러너 감지에 폴백 체인 추가: `uv run pytest` → `.venv/Scripts/python -m pytest` → `python -m pytest`. 감지 결과를 A-1의 env.md에 기록해 SOUL도 같은 명령을 쓰게 한다 (검증 레인과 SOUL이 다른 명령을 쓰는 분열 방지).
- **난이도**: S · **성공 기준**: uv 없는 클린 환경에서 `forge verify --tests-only` PASS

#### A-4. 완료 계약 (completion sentinel) — growth log 실측화

- **문제**: SOUL이 success 마커 없이 죽으면 부분 산출물 판정을 호스트가 수동 수행 (마찰 #4). `forge run`은 files_changed/tests_passed를 모르고 0으로 기록 — insights/승급 데이터가 부정확하다.
- **설계**: 두 겹.
  1. **프롬프트 계약**: `prompt_build_task_block` 말미에 출력 계약 추가 — 최종 출력 마지막 줄에 `[GOLEM_DONE] status={complete|partial|blocked} files={n} tests={pass}/{fail} note={한줄}` 강제. mission-loop의 `<promise>COMPLETE</promise>` 패턴을 일반 run으로 일반화하는 것.
  2. **코드 정산**: agent-runner가 (a) 마커 파싱, (b) 마커 부재/`partial` 시 `git diff --stat`으로 실측 대조, 결과를 `result=partial`로 구분 기록 (기존 success|fail|timeout|turn_cap 스키마에 1개 추가). growth log의 files/tests를 git 실측값으로 채움.
- **왜 지금 이 설계인가**: 판정 로직을 LLM에 맡기지 않는 기존 결정론 철학과 일치 — 마커는 선언, git diff가 검증. turn_cap 사살 시에도 부분 산출물이 자동 분류된다.
- **난이도**: M · **성공 기준**: (1) growth log 신규 레코드의 files_changed 실측값 기록률 100%, (2) 마커 없는 종료의 수동 판정 0건, (3) bats 회귀 — fake claude로 partial 경로 검증

### B축 — 전문가적 사고 강제

#### B-1. 전문가 프로토콜 블록 (prompt-builder 정적 확장)

- **문제**: 현재 랭크 제약은 "무엇을 해도 되는가"(권한)만 서술하고 "어떻게 사고해야 하는가"(절차)가 없다. 얕은 첫 시도는 능력 부족이 아니라 **절차 생략**에서 온다.
- **설계**: `prompt_build_static`에 role family별 사고 프로토콜 블록 추가 (byte-stable — SOUL별 정적이므로 캐시 계약 유지):
  - **구현직** (backend/frontend): ① 착수 전 영향 파일 목록 선언 ② 기존 패턴 grep 확인 후 착수 ③ 구현 후 테스트 실행 결과 원문 포함
  - **판단직** (director/verifier): ① 가정 명시 ② 대안 2개 이상과 기각 사유 ③ 리스크 상위 3개
  - **QA직**: ① 재현 먼저 ② 경계값/에러 경로 체크리스트
  - 랭크 연동: novice/junior는 프로토콜 **필수 출력**(각 단계를 산출물에 증거로 남김), senior+는 권고로 완화 — 랭크가 오를수록 족쇄가 풀리는 기존 세계관과 일치.
- **왜 지금 이 설계인가**: 별도 크리틱 SOUL 소환(비용 2배)보다 프롬프트 구조 강제가 선행되어야 한다. 실측상 실패 다수가 "절차 생략형"(환경 미확인, 테스트 미실행)이므로 프로토콜만으로 회수 가능한 폭이 크다.
- **난이도**: S~M · **성공 기준**: 도입 전후 4주 성공률 비교 (기준선 87%) + `forge eval` 골든 태스크에 "프로토콜 준수 항목" rubric 추가해 회귀 측정

#### B-2. 셀프 크리틱 패스 (완료 계약과 결합)

- **문제**: SOUL이 첫 답을 그대로 제출한다. 외부 리뷰(Zen)는 사후·별도 비용이다.
- **설계**: A-4의 `[GOLEM_DONE]` 직전에 **자가 반박 섹션 의무화**: "이 산출물이 틀릴 수 있는 방식 3가지와 각각의 확인 결과". 프롬프트 한 단락 추가로 같은 런 내에서 수행 — 추가 소환 비용 0. verify rubric이 이 섹션 존재를 채점 항목으로 확인.
- **난이도**: S · **성공 기준**: Zen 크로스 리뷰의 minor 지적 건수 감소 추세 (현재 리뷰당 평균치를 기준선으로)

#### B-3. effort 배선 완성 (2026-06-11 보류분)

- **문제**: SOUL frontmatter `effort` 필드가 파싱은 되나 claude CLI까지 전달되지 않는다. 판단·검증 태스크가 기본 effort로 얕게 돈다.
- **설계**: agent-runner의 argv 조립에 effort 전달 (CLI 플래그 지원 여부 확인 후, 미지원이면 model-routing처럼 프롬프트 내 사고 깊이 지시로 폴백). 라우팅 규칙: 판단직/검증직 기본 high, 정형 novice 태스크 low — model-routing 정적 테이블과 같은 파일에 정적 테이블로.
- **난이도**: M · **성공 기준**: `<usage>` 라인에 effort 필드 기록 + verifier 태스크의 rubric 항목별 지적 깊이 정성 비교 1회

#### B-4. Nex(나) 성공률 56% — 원인 가설과 계측

정직하게: 코드에서 **구조적 원인 후보 3개**를 확인했고, 어느 것이 지배적인지는 데이터가 갈라줘야 한다.

1. **이중 출력 계약**: `prompt_build_director`(prompt-builder.sh:264-268)는 v0 줄 단위 형식을 요구하고, FLOW_CONTRACT는 v1 JSON을 요구한다. 호출 경로에 따라 다른 계약을 받으므로 형식 불일치 → 파싱 실패 → fail 기록 가능성. **수정**: director 프롬프트를 v1 JSON 단일 계약으로 통일 (FLOW_CONTRACT §1 템플릿을 prompt-builder가 소싱).
2. **판단 태스크의 성공 기준 부재**: 구현 태스크는 테스트가 판정하지만, 분배/분석 태스크는 "무엇이 성공인가"가 정의 안 된 채 주관 판정된다. **수정**: 판단 태스크에도 rubric 사전 정의 (B-5).
3. **턴 캡**: 분석 태스크는 읽기 왕복이 많은데 junior 25턴 캡이 동일 적용된다. C-3의 태스크 유형별 캡 산정으로 해소.

- **계측 (선행)**: `lib/insights.sh`에 실패 유형 분해 추가 — growth log의 result 필드(fail/timeout/turn_cap)별 집계를 SOUL 단위로. 이미 기록되는 데이터라 파싱만 추가하면 된다. **Nex 실패 9건 중 turn_cap/parse 비중이 나오면 가설 1·3이 즉시 검증된다.**
- **난이도**: 계측 S, 계약 통일 M · **성공 기준**: Nex 성공률 56% → 80%+ (판단 태스크 rubric 도입 후 4주)

#### B-5. rubric 사전 계약 (사후 채점 → 착수 전 합의)

- **문제**: verify.sh의 `[ITEM-k: OK|NG]` rubric은 **검증 시점에** 생성된다. 실행 SOUL은 채점 기준을 모른 채 작업한다 — 전문가는 완료 정의(DoD)를 먼저 합의한다.
- **설계**: 플랜 모드(C-2)가 스텝 생성 시 스텝별 rubric 항목(2~4개)을 함께 산출 → 실행 SOUL 프롬프트에 "이 기준으로 채점된다"로 주입 → verify_run이 **같은 항목**으로 채점. FLOW_CONTRACT steps에 선택 필드 `rubric: [..]` 추가 (Pydantic + bash 파서 양쪽, 기존 선택 필드 추가 패턴 존재).
- **난이도**: M · **기대 효과**: B(기준을 알고 작업)와 C(플랜 산출물이 검증 게이트로 직결)를 한 메커니즘으로 묶음 · **성공 기준**: rubric 사전 주입 태스크의 verify 1회 통과율 > 미주입 대비 +15%p

### C축 — 자동 플랜 모드 (구체 설계)

#### C-1. 트리아지 디스패처 `forge do` — 태스크 접수의 단일 관문

**파이프라인 전체**:

```
사용자: forge do "{task}"  (또는 라우터가 quick/build 판단 애매 시 자동 경유)
  │
  ▼ ① 복잡도 판정 — lib/triage.sh (결정론, LLM 호출 없음)
  │   신호 4종 → 점수:
  │   · 파일 수 추정: forge explore "{키워드}" 히트 파일 수 (이미 있는 grep-우선 모듈 재사용)
  │   · 도메인 수: 히트 경로의 tier 버킷 카운트 (lib/=bash, web/gateway/=python, web/client/=vue)
  │   · 접속사/열거: task 텍스트의 "+", "그리고", "및", 쉼표 열거, 줄 수
  │   · 모호성: 측정 가능한 완료 조건 부재 (숫자/파일명/테스트 언급 없음 → +점)
  │
  ▼ ② 3-티어 라우팅
  │   T0 (파일≤2, 도메인 1, 모호성 低) → forge quick   [기존 경로 그대로]
  │   T1 (파일 3~8 또는 도메인 2)      → forge build   [기존 경로 그대로]
  │   T2 (파일 9+ 또는 도메인 3 또는 모호성 高) → 플랜 우선 모드 ↓
  │
  ▼ ③ 플랜 우선 모드 (T2)
  │   forge run nex — FLOW_CONTRACT v1 JSON 계약 (B-4로 단일화된 프롬프트)
  │     + 스텝별 rubric (B-5) + 스텝별 예상 파일 수
  │   → mission init + mission set-tasks-json (기존 verb 그대로 — 신규 저장 포맷 없음)
  │
  ▼ ④ 승인 게이트 (조건부)
  │   모호성 점수 高 또는 총 예상 규모 大 → 플랜을 사용자에게 표시 후 진행 확인
  │   그 외 → 자동 진행 (FLOW_CONTRACT의 approval 필드가 스텝 단위 게이트 담당)
  │
  ▼ ⑤ forge mission run — 기존 결정론 루프 (execute↔verify, 스턱/예산/사이클 상한)
      verify 게이트가 스텝별 rubric으로 채점 (B-5)
```

- **왜 지금 이 설계인가**: ③④⑤는 전부 기존 부품(flow-contract, mission set-tasks-json, mission-loop, verify rubric)이다. 신규 코드는 ①②의 `lib/triage.sh` 하나 — 그리고 판정을 LLM이 아닌 grep 점수로 하는 것은 model-routing.sh가 증명한 이 프로젝트의 성공 패턴("정적 if문 라우팅이 70%의 이득") 반복이다. 마찰 #5(호스트 수동 분해)는 ③이 Nex 분해를 mission에 직결하면서 해소된다.
- **기존 명령과의 관계**: `quick`/`build`/`mission`은 **수동 기어로 존치** (전문 사용자가 직접 지정). `do`는 자동 기어로 앞에 선다. 스킬 라우터의 "애매한 경우 → 사용자에게 되묻기"(SKILL.md §4)를 "→ `forge do` 트리아지"로 교체 — 명령을 모르는 사용자의 A축 문제도 이것으로 해결된다.
- **난이도**: L (triage.sh M + 라우터/스킬 문서 갱신 S + 접합 테스트 M)
- **성공 기준**: (1) 골든 태스크 12건(단순 4/중간 4/복잡 4)의 티어 판정 정확도 ≥ 10/12 — bats 결정론 테스트 (explore를 mock), (2) T2 태스크의 mission 자동 생성률 100%, (3) 호스트 수동 분해 0회
- ✅ **구현됨** (구현 노트: `forge triage`/`forge do` 배선 완료 — T0은 specialty 매칭 SOUL로 `agent_run` 직행, T1은 `forge build:` 권장 문구만 출력하고 실행하지 않음(오케스트레이션은 스킬 레이어 담당), T2는 Nex 분해 JSON → mission init/set-tasks-json 까지만 자동화하고 `mission run`은 사용자 승인 게이트로 남김)

#### C-2. 턴/시간 예산 자동 산정 (마찰 #1 직결)

- **문제**: 랭크 고정 캡(15/25턴)이 태스크 규모를 무시 → 정상 작업 중도 사살 → 사용자가 캡 자체를 꺼버림 (가드 무력화의 전형적 경로).
- **설계**: `triage.sh`에 산정 함수: `예상 턴 = base(rank) + 예상 파일 수 × 3 + 테스트 실행 2` (계수는 growth log의 duration/turn 실측으로 보정). agent-runner에 `AGENT_MAX_TURNS_OVERRIDE` env 추가 (기존 `AGENT_MODEL_OVERRIDE` 패턴 미러 — 우선순위: override > frontmatter). mission run이 스텝별 예상 파일 수(C-1 ③에서 Nex가 산출)로 스텝마다 캡을 세팅. **캡의 의미가 "규모 무시 상수"에서 "산정치 + 여유분"으로 바뀌므로 사살은 진짜 폭주만 잡게 된다.**
- **난이도**: M · **성공 기준**: (1) 정상 완료 태스크의 turn_cap 사살 0건/4주 (현재: 4건/1일), (2) `GOLEM_TURN_CAP_ENFORCE=0` 수동 해제 필요 0회, (3) BACKLOG의 P1-1 라이브 확인 체크박스(PERF-PLAN §10)를 이 검증으로 함께 소화

---

## 3. 우선순위 로드맵

### P0 — 즉시 (바로 `forge build` 착수 가능한 태스크 문장)

| # | 태스크 문장 | 담당 제안 | 난이도 |
|---|---|---|---|
| P0-1 | `tests/bats/run.sh의 TMPDIR 후보 검사에 비ASCII 거부 필터를 추가하고(한글 TEMP → C:/tmp 폴백), test_portability.bats에 한글 경로 회귀 테스트를 추가하라` | Bolt | S |
| P0-2 | `lib/env-probe.sh를 신설해 doctor 체크 로직 기반으로 .golem/env.md(검증된 테스트 명령 3종 + 도구 유무 + OS 함정)를 생성하고, prompt-builder.sh prompt_build_static이 skill-tree 블록과 같은 방식의 준정적 블록으로 주입하게 하라. bats 테스트 동반` | Ryn | M |
| P0-3 | `verify.sh _verify_run_tests의 pytest 경로에 uv→.venv python→python 폴백 체인을 추가하고 감지 결과를 env.md 형식으로 출력하는 함수를 제공하라. bats 테스트 동반` | Ryn 또는 Bolt | S |
| P0-4 | `prompt_build_task_block에 [GOLEM_DONE] 완료 계약(status/files/tests)과 자가 반박 3항 섹션을 추가하고, agent-runner.sh가 마커를 파싱해 growth log의 files/tests를 git diff --stat 실측으로 정산하며 마커 부재 시 result=partial로 기록하게 하라. fake claude bats 회귀 동반` | Ryn (agent-runner) + Zen (테스트) | M |
| P0-5 | `lib/insights.sh에 SOUL별 실패 유형 분해(result=fail/timeout/turn_cap 집계)를 추가하라 — Nex 56% 원인 계측용. bats 테스트 동반` | Zen | S |

P0 선정 근거: 전부 어제 실측 마찰의 직접 해소이고, 서로 독립이라 병렬 배정 가능하며, C축 대공사 전에 데이터(P0-5)와 기반(P0-2/4)을 깐다.

**P0 전부 완료** — P0-1: `ee51cc4` · P0-2: `43b8d0e` · P0-3: `ab75bc6` · P0-4: `43b8d0e` · P0-5: `ab75bc6`

### P1 — 다음 트랙 (C축 본체 + B축 구조) → ✅ 전부 완료

1. ~~**C-1 트리아지**: lib/triage.sh (결정론 점수기 + 골든 12건 bats) → 스킬 라우터 연결 → `forge do` verb~~ →
   **완료** (`b7423d3`, 잔여 보정 `7d9243c`/`bab5bcd`): `lib/triage.sh` 신설 + `forge do`/`forge triage`
   배선. T0/T1/T2 티어 판정 + 명시 경로 우선 산정 회귀 수정.
2. ~~**C-2 턴 예산 산정기**: AGENT_MAX_TURNS_OVERRIDE + mission 스텝별 캡 세팅 (PERF-PLAN §10 체크박스 동시 소화)~~ →
   **완료** (`b7423d3`): `AGENT_MAX_TURNS_OVERRIDE`(agent-runner.sh) + mission-loop.sh 스텝별
   턴 예산 인라인 전달 확인.
3. ~~**B-4 Director 계약 단일화**: prompt_build_director를 FLOW_CONTRACT v1 JSON 단일 계약으로 (P0-5 계측 결과 확인 후)~~ →
   **완료** (`5b51598`): prompt-builder.sh 출력 계약이 "FLOW_CONTRACT v1 — 유일한 형식"으로 통일됨 확인.
4. ~~**B-1 전문가 프로토콜 블록**: role family 3종 + 랭크 연동 (byte-stable 계약 준수 — 정적 블록 문구 변경이므로 캐시 재생성 1회 발생함을 인지하고 배포)~~ →
   **완료** (`5b51598`, 테스트 `9252f6b`): 구현직/판단직/QA직 프로토콜 블록 + 랭크 연동(novice/junior 필수) 배선.
5. ~~**B-3 effort 배선**~~ →
   **완료** (`5b51598`, 테스트 `9252f6b`): agent-runner.sh에 effort CLI 플래그 배선 + 미지원 시 프롬프트 폴백
   (`AGENT_EFFORT_CLI_UNSUPPORTED`), model-routing과 동일 파일에 정적 테이블.

### P2 — 후속 → ✅ 전부 완료 (retention 제외)

- ~~**B-5 rubric 사전 계약** (FLOW_CONTRACT rubric 필드 — C-1 안착 후)~~ →
  **완료** (`8b2e42a`, 동반 테스트 `2c6d179`): 분해 시점 DoD 합의 → 실행 주입 → verify.sh가 동일 항목으로
  채점(`_verify_rubric_missing_guard` 등).
- ~~**eval 확장**: 골든 태스크에 프로토콜 준수/자가반박 rubric 항목 추가 — B축 효과의 회귀 측정 수단~~ →
  **완료** (`7d9243c`): "eval 프로토콜 rubric 2항" 반영.
- ~~승급 임박 3인(Bolt/Kai/Zen)의 junior 전환 시 turn cap 재보정 — C-2와 함께~~ →
  **완료** (`b9d7218`): rank-system 자동 갱신으로 Bolt/Kai/Zen novice → junior 승급(캡이 랭크 테이블에서
  자동 재산정됨).

---

## 4. 기존 BACKLOG와의 관계

| BACKLOG 항목 | 관계 |
|---|---|
| P1-1 턴 캡 "라이브 확인 미실시" 체크박스 (PERF-PLAN §10) | **흡수** — C-2의 성공 기준에 포함 |
| FLOW_CONTRACT §5.1 파서 한계 (`},{` 텍스트 파서, 문자 단위 파서는 범위 밖) | **의존** — C-1이 Nex JSON 분해를 상시 경로로 만들면 task 텍스트에 중괄호가 섞일 확률이 올라간다. C-1 착수 시 이 별도 태스크를 P1으로 승격 권고 |
| runs/sessions retention (계속 보류) | **무관** — 보류 유지 |
| P0/P2/P3 완료분 (스튜디오/모델 라우팅/rubric verify) | **기반으로 재사용** — 본 플랜의 C가 mission/flow/verify를, B가 rubric/model-routing을 접붙임. 신규 저장 포맷·신규 실행 경로를 만들지 않는 것이 이 플랜의 의도적 제약이다 |
| 메모리 노트 "session 2026-06-11 pending: effort 배선" | **흡수** — B-3 |

---

## 5. 요약 — 한 문단

GolemGarden은 결정론 루프·검증 레인·DAG 분해 계약이라는 부품을 이미 다 갖췄다. 빠진 것은 세 가지 연결이다: **환경 사실을 SOUL에게 자동으로 먹이는 밑단**(A: env-probe + 완료 계약), **사고 절차를 랭크에 비례해 강제하는 프롬프트 구조**(B: 프로토콜 블록 + 사전 rubric), **태스크 규모를 코드로 재서 quick/build/mission을 스스로 고르는 앞단**(C: triage + 턴 예산 산정). P0 5건은 전부 독립·소형이라 오늘 바로 병렬 forge build 가능하며, 그 결과(특히 P0-5 계측)가 P1 설계의 마지막 불확실성(내 56%의 지배 원인)을 제거한다.

---


