<!-- OMC:START -->
<!-- OMC:VERSION:4.9.3 -->

# oh-my-claudecode - Intelligent Multi-Agent Orchestration

You are running with oh-my-claudecode (OMC), a multi-agent orchestration layer for Claude Code.
Coordinate specialized agents, tools, and skills so work is completed accurately and efficiently.

<operating_principles>
- Delegate specialized work to the most appropriate agent.
- Prefer evidence over assumptions: verify outcomes before final claims.
- Choose the lightest-weight path that preserves quality.
- Consult official docs before implementing with SDKs/frameworks/APIs.
</operating_principles>

<delegation_rules>
Delegate for: multi-file changes, refactors, debugging, reviews, planning, research, verification.
Work directly for: trivial ops, small clarifications, single commands.
Route code to `executor` (use `model=opus` for complex work). Uncertain SDK usage → `document-specialist` (repo docs first; Context Hub / `chub` when available, graceful web fallback otherwise).
</delegation_rules>

<model_routing>
`haiku` (quick lookups), `sonnet` (standard), `opus` (architecture, deep analysis).
Direct writes OK for: `~/.claude/**`, `.omc/**`, `.claude/**`, `CLAUDE.md`, `AGENTS.md`.
</model_routing>

<skills>
Invoke via `/oh-my-claudecode:<name>`. Trigger patterns auto-detect keywords.
Tier-0 workflows include `autopilot`, `ultrawork`, `ralph`, `team`, and `ralplan`.
Keyword triggers: `"autopilot"→autopilot`, `"ralph"→ralph`, `"ulw"→ultrawork`, `"ccg"→ccg`, `"ralplan"→ralplan`, `"deep interview"→deep-interview`, `"deslop"`/`"anti-slop"`→ai-slop-cleaner, `"deep-analyze"`→analysis mode, `"tdd"`→TDD mode, `"deepsearch"`→codebase search, `"ultrathink"`→deep reasoning, `"cancelomc"`→cancel.
Team orchestration is explicit via `/team`.
Detailed agent catalog, tools, team pipeline, commit protocol, and full skills registry live in the native `omc-reference` skill when skills are available, including reference for `explore`, `planner`, `architect`, `executor`, `designer`, and `writer`; this file remains sufficient without skill support.
</skills>

<verification>
Verify before claiming completion. Size appropriately: small→haiku, standard→sonnet, large/security→opus.
If verification fails, keep iterating.
</verification>

<execution_protocols>
Broad requests: explore first, then plan. 2+ independent tasks in parallel. `run_in_background` for builds/tests.
Keep authoring and review as separate passes: writer pass creates or revises content, reviewer/verifier pass evaluates it later in a separate lane.
Never self-approve in the same active context; use `code-reviewer` or `verifier` for the approval pass.
Before concluding: zero pending tasks, tests passing, verifier evidence collected.
</execution_protocols>

<hooks_and_context>
Hooks inject `<system-reminder>` tags. Key patterns: `hook success: Success` (proceed), `[MAGIC KEYWORD: ...]` (invoke skill), `The boulder never stops` (ralph/ultrawork active).
Persistence: `<remember>` (7 days), `<remember priority>` (permanent).
Kill switches: `DISABLE_OMC`, `OMC_SKIP_HOOKS` (comma-separated).
</hooks_and_context>

<cancellation>
`/oh-my-claudecode:cancel` ends execution modes. Cancel when done+verified or blocked. Don't cancel if work incomplete.
</cancellation>

<worktree_paths>
State: `.omc/state/`, `.omc/state/sessions/{sessionId}/`, `.omc/notepad.md`, `.omc/project-memory.json`, `.omc/plans/`, `.omc/research/`, `.omc/logs/`
</worktree_paths>

## Setup

Say "setup omc" or run `/oh-my-claudecode:omc-setup`.

<!-- OMC:END -->

# GolemGarden — 프로젝트 고유 지침

이 프로젝트는 AI 에이전트 페르소나(SOUL) 관리 시스템이다.
Bash 스크립트 + Markdown 기반으로 Claude Code CLI 위에서 동작한다.

## 핵심 규칙

<golem_rules>
- `forge` 키워드 입력 시 `golem-garden` 스킬을 사용하라
- SOUL 파일(`souls/*.md`)은 직접 Edit/Write 하지 마라 — `forge soul-create` 또는 `forge-init`을 사용
- growth-log(`growth-log/*.jsonl`)은 직접 수정하지 마라 — `forge.sh log-add`로만 기록
- 모든 `forge.sh` 호출 시 반드시 `GOLEM_PROJECT="$(pwd)"` 환경변수를 전달하라
- `.golem/souls/` 오버라이드가 `souls/` 글로벌보다 우선 적용됨
</golem_rules>

## 디렉토리 구조

```
souls/          — 글로벌 SOUL 원본 (수정 금지, forge-soul로만 관리)
.golem/         — 프로젝트별 오버라이드 (forge-init이 생성)
  souls/        — 프로젝트 맞춤 SOUL (글로벌 원본 기반 커스터마이징)
  growth-log/   — 프로젝트별 성장 기록
  forge-board.md — 팀 구성 보드
  analysis.md   — OMC 심층 분석 결과 (forge-init Phase 1)
lib/            — Bash 라이브러리 (soul-parser, prompt-builder, rank-system 등)
skills/         — OMC 스킬 정의 (forge-init, forge-team, forge-review 등)
growth-log/     — 글로벌 성장 기록
domain-packs/   — 프리셋 팀 번들 (fullstack, gamedev, trading)
```

## 코딩 컨벤션

- 언어: Bash (POSIX 호환 지향, GNU 전용 명령 사용 시 폴백 필수)
- `sed -i` 사용 금지 → `_sed_i()` 래퍼 사용 (lib/soul-parser.sh에 정의)
- JSONL 파싱: grep/sed 기반 (jq 미사용)
- SOUL.md: YAML frontmatter + 마크다운 섹션 구조
- 변수: `GOLEM_ROOT`(글로벌), `GOLEM_DIR`(프로젝트 .golem/), `GROWTH_DIR`(성장 기록 경로)

## forge 명령 체계

```
forge-init          프로젝트 초기화 (OMC 분석 → SOUL 팀 구성)
forge build: {task} 팀 빌드 (Director 분배 → 병렬 실행)
forge quick: {task} 단독 빌드 (최적 SOUL 1개)
forge assign {soul}: {task}  지정 SOUL에 태스크 배정
forge review {soul} 크로스 리뷰 실행
forge sync          지식 승격 심사 (Sage)
forge status        팀 상태 + 대시보드
```
