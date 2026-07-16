# GolemGarden — 프로젝트 고유 지침

이 프로젝트는 AI 에이전트 페르소나(SOUL) 관리 시스템이다.
Bash 스크립트 + Markdown 기반으로 Claude Code CLI 위에서 동작한다.

> 핵심 철학과 작업 규약은 `PHILOSOPHY.md`를 참조.
> "SOUL은 족쇄가 아니라 나침반" — 능력을 제한하지 않고 방향만 잡아준다.

## 절대 규칙 (CRITICAL — 예외 없음)

<golem_rules_critical>
**1. forge 스킬 강제 호출**
사용자 입력에 "forge", "포지", "forje" 또는 SOUL 이름 + 태스크가 포함되면
반드시 Skill 도구로 `golem-garden` 스킬을 호출하라.
직접 forge.sh를 실행하거나, 스킬 없이 작업을 수행하는 것은 금지한다.
이 규칙은 어떤 상황에서도 우회할 수 없다.

**2. SOUL 실행 가시성 (누가 뭘 하는지 표시)**
SOUL을 Agent로 소환할 때 반드시 아래 형식으로 사용자에게 먼저 표시하라:
```
──────────────────────────────────
>> {SOUL_NAME} ({role}) 작업 시작
   태스크: {task_summary}
   모델: {model} | 랭크: {rank} | 도구: {tools}
──────────────────────────────────
```
Agent 호출 전에 이 메시지를 출력해야 한다. 생략 금지.
병렬 실행 시 각 SOUL마다 개별 표시한다.
완료 시에도 결과를 SOUL별로 표시한다:
```
<< {SOUL_NAME} 완료 — {result} ({files}파일, {tests}테스트)
```

**3. 보호 대상 직접 수정 금지**
아래 파일은 절대 Edit/Write로 직접 수정하지 않는다:
- SOUL 파일: `souls/*.md`, `.golem/souls/*.md` → `forge soul-create` 사용
- 성장 기록: `growth-log/*.jsonl`, `.golem/growth-log/*.jsonl` → `forge log-add` 사용
- 메일박스: `.golem/mailbox/*.jsonl` → `forge mailbox` 명령 사용
- 업적/케미: `achievements.jsonl`, `chemistry.jsonl` → forge 명령 사용
</golem_rules_critical>

## 운영 규칙

<golem_rules>
- 모든 `forge.sh` 호출 시 반드시 `GOLEM_PROJECT="$(pwd)"` 환경변수를 전달하라
- `.golem/souls/` 오버라이드가 `souls/` 글로벌보다 우선 적용됨
- SOUL 소환 시 `tools` frontmatter를 OMC agent `allowed_tools`로 전달
- SOUL `maxTurns`는 하네스가 코드로 강제한다 — 스트림의 assistant 메시지 수를 라이브 카운트,
  초과 시 프로세스 트리 kill + growth-log `result=turn_cap` (P1-1, GOLEM_TURN_CAP_ENFORCE=0 로 해제)
- 모델 라우팅(P2-1): frontmatter `model:` 명시가 항상 우선. 미지정/`auto`면 lib/model-routing.sh
  정적 테이블(판단직→opus, expert/master→sonnet, 정형 novice→haiku, 기본 sonnet)이 결정
- Director(Nex)는 코드를 직접 작성하지 않음 — 반드시 SOUL에 위임
- Novice/Junior SOUL은 병렬 쓰기 금지 — 파일 충돌 위험
</golem_rules>

## 자동 보호 훅 (settings.json)

아래 훅이 자동으로 동작하며, 위 규칙을 시스템 레벨에서 강제한다:
- **PreToolUse(Edit/Write)**: growth-log, mailbox JSONL 직접 수정 시도 → 차단
- **PostToolUse(Edit)**: Novice SOUL의 멀티파일 수정 → 경고
- **Stop**: 세션 종료 시 성장 기록 자동 저장 + 대시보드 자동 갱신

## 디렉토리 구조

```
souls/          — 글로벌 SOUL 원본 (수정 금지, forge-soul로만 관리)
.golem/         — 프로젝트별 오버라이드 (forge-init이 생성)
  souls/        — 프로젝트 맞춤 SOUL (글로벌 원본 기반 커스터마이징)
  growth-log/   — 프로젝트별 성장 기록
  mailbox/      — SOUL 간 통신 (JSONL 메일박스)
  sessions/     — 세션 트랜스크립트 + 메타데이터
  forge-board.md — 팀 구성 보드
  analysis.md   — OMC 심층 분석 결과 (forge-init Phase 1)
lib/            — Bash 라이브러리
  soul-parser.sh    — SOUL 파싱 + 새 필드(tools, maxTurns, isolation, effort)
  growth-log.sh     — 성장 기록 + 비용 추적
  prompt-builder.sh — 캐시 최적화 프롬프트 조립
  mailbox.sh        — SOUL 간 파일 기반 통신
  session.sh        — 세션 지속성 (생성/재개/상태)
  error-recovery.sh — 3단계 실패 복구 (재시도→위임→에스컬레이션)
  budget.sh           — 예산 추적 + 수확체감 감지
  tool-character.sh   — 도구 성격 메타데이터
  soul-memory.sh      — SOUL별 학습 기억
  retrospective.sh    — 자동 회고
  chemistry.sh        — 팀 케미 추적
  achievement.sh      — 업적/뱃지
  skill-tree.sh       — 전문화 분기
  project-dna.sh      — 프로젝트 지문
  agent-runner.sh   — 엔진 네이티브 SOUL 소환 (claude CLI 직접, 타임아웃/예산 가드)
  mission.sh        — 단일 목표 완주 모드 (spec.md + state.json)
  studio.sh         — 독립 플로우 스튜디오 (프로젝트 외부 폴더 = 자기완결 실행 단위)
  verify.sh         — 검증 레인 ([VERDICT:] 마커 계약 + 결정론 테스트)
  eval.sh           — 골든 태스크 스위트 (모델 회귀 측정)
  doctor.sh         — 엔진 진단 / explore.sh — grep-우선 코드 컨텍스트 / insights.sh — 성과 분석
  rank-system.sh, forge-review.sh, forge-board.sh, portability.sh, forge-soul.sh, domain-pack.sh, knowledge-sync.sh
skills/         — 스킬 정의 (forge-init, forge-team, forge-review, forge-studio 등 — 엔진 네이티브)
templates/      — 빌트인 리소스 템플릿
  souls/flowsmith.md — 워크플로우 아키텍트 SOUL (`studio init`이 스튜디오 로컬 `.golem/souls/`로 복사)
growth-log/     — 글로벌 성장 기록
domain-packs/   — 프리셋 팀 번들 (fullstack, gamedev, trading, physical-ai)
tests/          — 테스트
  bats/         — Bash 단위 테스트 (bats-core 1.11.0 vendored, run.sh 진입점)
web/            — 3-tier 웹 스택 (Tier B/C 도입)
  gateway/      — Python FastAPI Gateway (uv, pytest, sessions.db)
    src/golem_gateway/
      growth_log.py  — chat 종료 후크 (Bash growth-log.sh 와 동일 schema 로 jsonl 기록)
      sessions_db.py — SQLite WAL + PRAGMA user_version 자동 마이그레이션
      souls.py       — Pydantic SoulDetail (6 필드 노출)
      activity.py    — forge-board.md 파서 (강조 셀 평탄화)
    tests/      — pytest (187 케이스)
  client/       — Vue 3 + Pinia + Naive UI (Node 23+, vite, vitest happy-dom)
    src/components/hermes/souls/SoulDetailModal.vue — director 격리 시각화
    tests/      — vitest (13+ 케이스)
  setup.ps1     — Windows 통합 셋업 (한글 username junction, env, deps)
```

## 코딩 컨벤션

- 언어: Bash (POSIX 호환 지향, GNU 전용 명령 사용 시 폴백 필수)
- `sed -i` 사용 금지 → `_sed_i()` 래퍼 사용 (lib/soul-parser.sh에 정의)
- JSONL 파싱: grep/sed 기반 (jq 미사용)
- SOUL.md: YAML frontmatter + 마크다운 섹션 구조
- 변수: `GOLEM_ROOT`(글로벌), `GOLEM_DIR`(프로젝트 .golem/), `GROWTH_DIR`(성장 기록 경로)

## forge 명령 체계

`※` 표시는 **스킬 라우터 명령** — CLI verb 가 아니라 golem-garden 스킬(LLM)이
해석해 `forge run`/forge-team 등 원시 명령으로 번역한다. `bash forge.sh build: ...`
처럼 직접 실행하면 실패한다. 나머지는 forge.sh dispatch 의 CLI 원시 verb.

```
forge overview (ov)     통합 대시보드 — 팀/성과/비용/활동 한눈에
forge-init              프로젝트 초기화 (프로젝트 분석 → SOUL 팀 구성) ※스킬
forge run {soul} "{task}" [uuid]  엔진 네이티브 SOUL 소환 (모든 실행의 기본 단위)
forge run --continue {run_id}  사살(타임아웃/턴캡)된 런을 체크포인트에서 이어달리기 (R-1, 슬라이스 상한 3)
forge triage "{task}"   태스크 복잡도 판정 (결정론 점수기 — TRIAGE tier=T0/T1/T2 라인 출력)
forge do "{task}"       자동 기어 — T0: 단일 SOUL 직행 / T1: build 권고 / T2: Nex 분해→mission 생성
forge build: {task}     팀 빌드 (Director 분배 → 병렬 실행) ※스킬
forge quick: {task}     단독 빌드 (최적 SOUL 1개) ※스킬
forge assign {soul}: {task}  지정 SOUL에 태스크 배정 ※스킬
forge mission run {id} [soul] [verifier]  결정론 자율 루프 — execute↔verify 반복,
                        사이클/재시도 상한·예산 센티널·스턱 디텍터 코드 강제
forge mission init/set-tasks/set-tasks-json/next/task/status/list/complete
                        미션 스펙·상태 관리 (set-tasks-json = Nex 분해 JSON 직결)
forge studio init [dir] [name] [goal]  독립 플로우 스튜디오 스캐폴드 (자기완결 폴더, 멱등)
forge studio design [dir] "{goal}"  flowsmith 소환 → 에이전트 팀 + 플로우 자동 생성
forge studio agent-add [dir] {name} {model} {role} [rules]  스튜디오 로컬 SOUL 생성
forge studio run [dir] [flow_id]  스튜디오 최신(또는 지정) 플로우 실행
forge studio status [dir] / forge studio list  스튜디오 요약 / 전체 레지스트리
forge verify {target} [soul]  검증 레인 (결정론 테스트 + [VERDICT:] 마커 심판)
forge eval [--model m]  골든 태스크 스위트 (모델 회귀 측정) / eval list / eval report
forge doctor            엔진 헬스체크
forge explore {query}   grep-우선 코드 컨텍스트
forge review {soul}     크로스 리뷰 실행
forge sync              지식 승격 심사 (Sage) ※스킬
forge status            팀 상태 + 대시보드
forge dashboard --cost  비용 대시보드 (SOUL별 토큰/USD)
forge mailbox dashboard 메일박스 현황
forge mailbox send ...  SOUL 간 메시지 전송
forge session create    세션 생성
forge session resume    세션 재개
forge session status    세션 상태
forge recover-history {soul}  복구 이력 조회 (구 forge recover 는 무동작이라 제거 —
                        재시도 실행은 mission run 루프가 담당)
forge worktree create   SOUL별 격리 worktree 생성
forge worktree merge    Worktree 변경사항 머지
forge worktree status   활성 worktree 현황
forge memory dashboard  SOUL 학습 기억 현황
forge retro latest      최근 회고 보기
forge chemistry dashboard 팀 케미 대시보드
forge achievement dashboard 업적 대시보드
forge skill-tree dashboard  전문화 현황
forge dna show          프로젝트 DNA 조회
forge budget status     예산 상태
forge tool-char guide   도구 성격 가이드
forge insights            팀 전체 인사이트 (성과 패턴 분석)
forge insights {soul}     SOUL별 성과 분석 (추세, 비용 효율, 학습 영역)
forge skill-export --all  SOUL → Agent Skill 내보내기 (agentskills.io 호환)
forge skill-import <dir>  Agent Skill → SOUL 임포트
forge log-add {soul} {task} {result}  성장 기록 직접 추가 (gateway growth_log 후크의 정식 진입점)
```
