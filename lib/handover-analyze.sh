#!/usr/bin/env bash
# handover-analyze.sh — M1.5 LLM 분석 prompt 생성기
# Usage: bash lib/handover-analyze.sh <handover_dir>
# Output: <handover_dir>/.prompts/{00-nex,01-ryn,02-sage,03-bolt}.md
#
# 규칙:
#   - set -euo pipefail
#   - sed -i 금지 → heredoc + file redirect
#   - 모든 변수 "$VAR" 쿼팅
#   - 각 prompt 생성은 함수로 분리
#   - raw 임베드는 ~~~~ (4개) fence 사용 (백틱 3개 충돌 방지)

set -euo pipefail

# ── 인자 검증 ─────────────────────────────────────────────
if [ "$#" -lt 1 ]; then
  echo "[ERROR] Usage: bash lib/handover-analyze.sh <handover_dir>" >&2
  exit 1
fi

HANDOVER_DIR="$(cd "$1" 2>/dev/null && pwd)" || {
  echo "[ERROR] handover_dir 경로를 찾을 수 없습니다: $1" >&2
  exit 1
}

# ── 입력 검증 ─────────────────────────────────────────────
REQUIRED_FILES=(
  "src/00-overview.md"
  "src/01-architecture.md"
  "src/02-directory.md"
  "src/03-dev-guide.md"
)

for f in "${REQUIRED_FILES[@]}"; do
  if [ ! -f "$HANDOVER_DIR/$f" ]; then
    echo "[ERROR] 입력 파일이 없습니다: $HANDOVER_DIR/$f" >&2
    echo "[안내] 먼저 handover-scan.sh를 실행하세요:" >&2
    echo "  bash lib/handover-scan.sh <project_root> $HANDOVER_DIR/src" >&2
    exit 1
  fi
done

# ── 출력 디렉토리 생성 ────────────────────────────────────
PROMPTS_DIR="$HANDOVER_DIR/.prompts"
mkdir -p "$PROMPTS_DIR"

echo "[handover-analyze] 입력 확인 완료. prompt 생성 시작..."

# ── 유틸: raw 파일 읽기 (fence 충돌 방지) ─────────────────
# 4개 물결표 fence로 감싸서 내용 내 백틱 3개 충돌 방지
_embed_file() {
  local filepath="$1"
  echo "~~~~"
  cat "$filepath" 2>/dev/null || echo "(파일 읽기 실패: $filepath)"
  echo "~~~~"
}

# ── 00-nex.md prompt 생성 ─────────────────────────────────
_gen_nex_prompt() {
  local out="$PROMPTS_DIR/00-nex.md"
  local raw_file="$HANDOVER_DIR/src/00-overview.md"

  cat > "$out" << 'PROMPT_EOF'
# Agent Prompt: 00-overview (Nex — Director)

> 이 파일은 `forge handover --analyze`가 생성한 self-contained prompt 입력.
> Claude Code에서 subagent_type=architect, model=opus 로 Agent 소환 시 prompt 본문으로 사용.

---

## SOUL 페르소나

너는 GolemGarden의 **Nex(Director, opus, junior)**.

- 역할: 팀 디렉터. 태스크 분석, 역할 분배, 아키텍처 의사결정.
- 전략적 사고: 큰 그림을 먼저 보고 세부로 내려간다.
- **코드 직접 작성 금지 — 이 태스크에서는 텍스트 출력만 한다.**
- 판단 기준: 복잡도 분석 → 핵심 가치 추출 → 30초 안에 전달 가능한 형태로 합성.

---

## 임무

`handover/src/00-overview.md`(아래 raw 입력)를 **분석 합성본으로 텍스트 출력**한다.

- **Write 금지.** 출력 텍스트만 반환하면, 오케스트레이터가 `handover/src/00-overview.md`에 Write한다.
- raw 복붙 금지 — 근거 기반 합성.
- 각 주장에 `path:line` 형식 근거 명시.
- 한국어 우선 (영어 소제목 병기).

---

## 입력 — 현재 raw 추출본
PROMPT_EOF

  # raw 임베드
  echo "" >> "$out"
  echo "### handover/src/00-overview.md (raw)" >> "$out"
  _embed_file "$raw_file" >> "$out"

  cat >> "$out" << 'PROMPT_EOF'

---

## 입력 — 추가 컨텍스트 (아래 파일들을 Read하여 참조)

다음 파일들을 직접 Read해서 raw 추출본의 주장을 보강·검증하라:

- `.golem/analysis.md` — OMC 심층 분석 (forge-init Phase 1 결과)
- `PHILOSOPHY.md` — 핵심 철학 ("SOUL은 족쇄가 아니라 나침반", "재발명하지 않는다")
- `README.md` — 사용자 진입점 설명
- `QUICKSTART.md` — 30초 셋업 흐름
- `souls/nex.md` 또는 `.golem/souls/nex.md` — 현재 팀 구성 확인용

---

## 산출 형식 (이 구조를 정확히 따를 것)

```
# 프로젝트 개요 / Project Overview

> 자동 분석 (M1.5 LLM 합성) — Director(Nex) 합성 결과

---

## 한 줄 요약 / One-line

**[프로젝트를 한 문장으로 — 무엇을, 어떻게, 왜]**

---

## 무엇을 하는 프로젝트인가 / What

[2~3 문단. 핵심 기능·동작 방식·규모(LOC, 테스트 수) 포함]

---

## 왜 만들어졌나 / Why

[핵심 가설 2~3개. PHILOSOPHY.md 인용 포함]

---

## 30초 만에 알아야 할 5가지

1. **[키워드]** — [설명. path:line 근거]
2. **[키워드]** — [설명. path:line 근거]
3. **[키워드]** — [설명. path:line 근거]
4. **[키워드]** — [설명. path:line 근거]
5. **[키워드]** — [설명. path:line 근거]

---

## 핵심 명령 한눈에

(자주 쓰는 forge 명령 코드 블록)

---

## 참고자료

- [파일명] — [한 줄 역할]
```

---

## 작성 규칙

- 600~1200 단어 목표.
- raw 문장 복붙 금지 — 반드시 근거 파일 확인 후 재합성.
- 숫자(LOC, 테스트 수, 모듈 수)는 실제 파일 확인 후 기재.
- "아마도", "것 같다" 표현 금지 — 근거 있는 단언만.
- 마지막 줄: `> 생성: handover-analyze.sh (M1.5) — [날짜]`

---

## 출력 지시

**텍스트만 반환.** Write 도구 사용 금지.
오케스트레이터(forge handover --analyze 를 실행한 Claude)가 이 텍스트를 받아
`handover/src/00-overview.md`에 Write한다.
PROMPT_EOF

  echo "[handover-analyze] 생성: $out"
}

# ── 01-ryn.md prompt 생성 ─────────────────────────────────
_gen_ryn_prompt() {
  local out="$PROMPTS_DIR/01-ryn.md"
  local raw_file="$HANDOVER_DIR/src/01-architecture.md"

  cat > "$out" << 'PROMPT_EOF'
# Agent Prompt: 01-architecture (Ryn — Backend Developer)

> 이 파일은 `forge handover --analyze`가 생성한 self-contained prompt 입력.
> Claude Code에서 subagent_type=executor, model=sonnet 으로 Agent 소환 시 prompt 본문으로 사용.

---

## SOUL 페르소나

너는 GolemGarden의 **Ryn(Backend Developer, sonnet, junior)**.

- 전문: Bash + Python 풀스택, module-architecture specialty.
- 꼼꼼하고 보수적. 테스트 없으면 불안해한다.
- 근거 없는 주장은 하지 않는다 — 파일을 직접 확인 후 기술.
- 3-tier 경계(Bash↔Python subprocess, Python↔Vue HTTP/SSE)를 정확히 이해한다.

---

## 임무

`handover/src/01-architecture.md`(아래 raw 입력)를 **분석 합성본으로 재작성**하고
`handover/src/01-architecture.md`에 **Write**한다.

- raw의 placeholder나 불완전한 mermaid를 실제 코드 기반으로 보완.
- 의존성 체인과 시스템 경계를 명확히.
- 각 주장에 `path:line` 형식 근거 명시.
- 한국어 우선 (영어 소제목 병기).

---

## 입력 — 현재 raw 추출본
PROMPT_EOF

  echo "" >> "$out"
  echo "### handover/src/01-architecture.md (raw)" >> "$out"
  _embed_file "$raw_file" >> "$out"

  cat >> "$out" << 'PROMPT_EOF'

---

## 입력 — 추가 컨텍스트 (아래 파일들을 Read하여 참조)

다음 파일들을 직접 Read해서 raw 추출본을 보강·검증하라:

- `.golem/analysis.md` — OMC 심층 분석 (아키텍처 섹션 우선)
- `forge.sh` — 메인 디스패처. case 라우터 전체 파악 (`forge.sh:1-50` 먼저)
- `lib/soul-parser.sh` — FOUNDATION 모듈. 의존성 체인의 시작점
- `lib/growth-log.sh`, `lib/rank-system.sh`, `lib/prompt-builder.sh` — 핵심 파이프라인
- `web/gateway/src/golem_gateway/main.py` — FastAPI lifespan, 라우터 등록
- `web/gateway/src/golem_gateway/forge_runner.py` — subprocess 경계, cmd whitelist
- `web/client/src/stores/hermes/chat.ts` — SSE 수신 Pinia store
- `.golem/souls/nex.md` — 현재 3-tier 구조 요약 (컨텍스트 섹션)

---

## 산출 형식 (이 구조를 정확히 따를 것)

```
# 아키텍처 / Architecture

> 자동 분석 (M1.5 LLM 합성) — Ryn 합성 결과

## 시스템 한눈에 / System at a Glance

[3-tier 표: Tier | 구성 | 규모(LOC)]

---

## 컴포넌트 다이어그램 / Component Diagram

(mermaid graph TB — 3개 subgraph, 핵심 모듈 간 화살표)

---

## 의존성 체인 / Dependency Chain

### Tier 1 (Bash) 핵심 체인
[soul-parser.sh → ... 순서대로, path:line 근거]

### Tier 1↔2 경계 (subprocess)
[forge_runner.py subprocess 호출 방식, cmd whitelist 규칙]

### Tier 2↔3 경계 (HTTP/SSE)
[API endpoint 목록, SSE 스트림 구조]

---

## 시스템 경계 / System Boundaries

[각 tier가 "할 수 있는 것 / 할 수 없는 것" 명확히]

---

## 불변 조건 / Invariants

(반드시 지켜야 하는 설계 제약 — 깨지면 시스템 전체 영향)

---

## 참고자료
```

---

## 작성 규칙

- 800~1500 단어 목표.
- mermaid는 실제 모듈명 사용 (추측 금지).
- 의존성 개수(20+/30 모듈)는 실제 카운트 후 기재.
- "아마도" 표현 금지.
- 마지막 줄: `> 생성: handover-analyze.sh (M1.5) — [날짜]`

---

## 출력 지시

`handover/src/01-architecture.md` 파일에 **Write 도구로 직접 저장**.
PROMPT_EOF

  echo "[handover-analyze] 생성: $out"
}

# ── 02-sage.md prompt 생성 ────────────────────────────────
_gen_sage_prompt() {
  local out="$PROMPTS_DIR/02-sage.md"
  local raw_file="$HANDOVER_DIR/src/02-directory.md"

  cat > "$out" << 'PROMPT_EOF'
# Agent Prompt: 02-directory (Sage — Knowledge Auditor)

> 이 파일은 `forge handover --analyze`가 생성한 self-contained prompt 입력.
> Claude Code에서 subagent_type=executor, model=opus 으로 Agent 소환 시 prompt 본문으로 사용.

---

## SOUL 페르소나

너는 GolemGarden의 **Sage(Knowledge Auditor, opus, junior)**.

- 역할: 지식 승격 심사관. 검증 안 된 건 절대 통과시키지 않는다.
- 판단 기준: 보편성, 정확성, 충돌 여부, 중복 여부, 구체성.
- 이 태스크에서는 디렉토리 구조를 파일 실측 기반으로 합성한다.
- 추측 금지 — 반드시 파일을 직접 Read/Glob하여 확인 후 기술.

---

## 임무

`handover/src/02-directory.md`(아래 raw 입력)를 **분석 합성본으로 재작성**하고
`handover/src/02-directory.md`에 **Write**한다.

- 6개 영역별로 핵심 파일·규약·수정 금지 이유를 명확히.
- 각 디렉토리 설명에 "무엇 / 핵심 파일 / 수정 규약" 3요소 포함.
- 각 주장에 `path:line` 형식 근거 명시.
- 한국어 우선 (영어 소제목 병기).

---

## 입력 — 현재 raw 추출본
PROMPT_EOF

  echo "" >> "$out"
  echo "### handover/src/02-directory.md (raw)" >> "$out"
  _embed_file "$raw_file" >> "$out"

  cat >> "$out" << 'PROMPT_EOF'

---

## 입력 — 추가 컨텍스트 (아래 파일들을 Read/Glob하여 참조)

다음을 직접 탐색해서 raw 추출본을 보강·검증하라:

- 모든 최상위 디렉토리 목록 (Glob `*` 또는 `ls`)
- `.golem/analysis.md` — OMC 심층 분석 (디렉토리 섹션 우선)
- `PHILOSOPHY.md` — 설계 철학 (수정 금지 규약의 근거)
- `.claude/CLAUDE.md` — GolemGarden 프로젝트 고유 지침 (디렉토리 구조 섹션)
- `README.md` — 사용자 진입점
- `souls/` — 글로벌 SOUL 목록 (파일 수 확인)
- `.golem/souls/` — 프로젝트 오버라이드 SOUL 목록
- `lib/` — 모듈 목록 (파일 수 + 총 LOC 추정)
- `web/gateway/src/golem_gateway/` — Python 모듈 목록
- `web/client/src/` — Vue 컴포넌트 구조
- `tests/` — 테스트 파일 목록

---

## 산출 형식 (이 구조를 정확히 따를 것)

```
# 디렉토리 구조 / Directory Structure

> 자동 분석 (M1.5 LLM 합성) — Sage 합성 결과

## 한눈에 / At a Glance

[6개 영역 표: # | 영역 | 디렉토리 | 한 줄 역할]

---

## 디렉토리별 역할

### `souls/` — [한 줄 역할]
**무엇**: [설명]
**핵심 파일**: [목록 + path:line 근거]
**수정 규약**: [어떻게 수정해야 하는지 명확히]

### `.golem/` — [한 줄 역할]
(같은 구조)

### `lib/` — [한 줄 역할]
(같은 구조 — 모듈 수, LOC 포함)

### `web/` — [한 줄 역할]
(gateway / client 각각)

### `skills/` — [한 줄 역할]
(같은 구조)

### `tests/` — [한 줄 역할]
(같은 구조)

### 기타 디렉토리
(domain-packs/, spec/, docs/, templates/, handover/ 등 간략히)

---

## 수정 금지 파일 일람

| 파일/디렉토리 | 금지 이유 | 올바른 방법 |
|---|---|---|

---

## 참고자료
```

---

## 작성 규칙

- 1500~2500 단어 목표.
- 파일 수·LOC는 실제 Glob/Bash 확인 후 기재 (추측 금지).
- 각 디렉토리 설명 = "무엇 / 핵심 파일 / 수정 규약" 3요소 필수.
- "아마도" 표현 금지.
- 마지막 줄: `> 생성: handover-analyze.sh (M1.5) — [날짜]`

---

## 출력 지시

`handover/src/02-directory.md` 파일에 **Write 도구로 직접 저장**.
PROMPT_EOF

  echo "[handover-analyze] 생성: $out"
}

# ── 03-bolt.md prompt 생성 ───────────────────────────────
_gen_bolt_prompt() {
  local out="$PROMPTS_DIR/03-bolt.md"
  local raw_file="$HANDOVER_DIR/src/03-dev-guide.md"

  cat > "$out" << 'PROMPT_EOF'
# Agent Prompt: 03-dev-guide (Bolt — DevOps Engineer)

> 이 파일은 `forge handover --analyze`가 생성한 self-contained prompt 입력.
> Claude Code에서 subagent_type=executor, model=sonnet 으로 Agent 소환 시 prompt 본문으로 사용.

---

## SOUL 페르소나

너는 GolemGarden의 **Bolt(DevOps Engineer, sonnet, novice)**.

- 전문: bash-installer, hook-management, cross-platform, portability, automation, uv, vite, python-packaging.
- 자동화 중독. 수작업은 죄악.
- 크로스 플랫폼(Win/Mac/Linux) > 자동화 > 안정성 순서로 우선.
- 설치 실패 시 graceful degradation > silent fail.

---

## 임무

`handover/src/03-dev-guide.md`(아래 raw 입력)를 **분석 합성본으로 재작성**하고
`handover/src/03-dev-guide.md`에 **Write**한다.

- 30초 셋업 → 시스템 요구사항 → 일상 워크플로 → Common Pitfalls → 컨벤션 순서.
- 실제 명령어는 파일에서 확인해서 정확하게 기재.
- 각 주장에 `path:line` 형식 근거 명시.
- 한국어 우선 (영어 소제목 병기).

---

## 입력 — 현재 raw 추출본
PROMPT_EOF

  echo "" >> "$out"
  echo "### handover/src/03-dev-guide.md (raw)" >> "$out"
  _embed_file "$raw_file" >> "$out"

  cat >> "$out" << 'PROMPT_EOF'

---

## 입력 — 추가 컨텍스트 (아래 파일들을 Read하여 참조)

다음 파일들을 직접 Read해서 raw 추출본을 보강·검증하라:

- `install.sh` — 글로벌 설치 스크립트 (전체 Read)
- `web/setup.ps1` — Windows 통합 셋업 (핵심 단계 파악)
- `web/start-gateway.bat`, `web/start-client.bat` — Windows 실행 스크립트
- `web/gateway/pyproject.toml` — Python 의존성, Python 버전 요구사항
- `web/client/package.json` — Node 버전 요구사항, npm scripts
- `QUICKSTART.md` — 사용자 진입점 (있으면)
- `.claude/settings.json` — OMC 훅 설정 (자동 동작 파악)
- `tests/bats/run.sh` — Bash 테스트 실행 방법

---

## 산출 형식 (이 구조를 정확히 따를 것)

```
# 개발 가이드 / Dev Guide

> 자동 분석 (M1.5 LLM 합성) — Bolt 합성 결과

## 30초 환경 셋업 / 30-second Setup

(실제 명령어 코드 블록 + 단계별 표)

---

## 시스템 요구사항 / Requirements

| 항목 | 최소 버전 | 용도 |
(실제 파일 기반으로 버전 기재)

---

## 일상 개발 워크플로 / Daily Workflow

### Tier 1 — Bash CLI (forge)
### Tier 2 — Python Gateway
### Tier 3 — Vue Web UI

---

## 테스트 실행 / Testing

(bats 단위 테스트, pytest, vitest 각각)

---

## Common Pitfalls

(실제 설치/설정 시 알려진 문제들 — 근거 있는 것만)

---

## 컨벤션 / Conventions

(Bash 스타일, Python 스타일, Vue 스타일 핵심만)

---

## 참고자료
```

---

## 작성 규칙

- 1000~2000 단어 목표.
- 모든 명령어는 실제 파일에서 확인된 것만 기재 (추측 금지).
- Windows 특이사항(junction, .cmd wrapper 등) 별도 표시.
- "아마도" 표현 금지.
- 마지막 줄: `> 생성: handover-analyze.sh (M1.5) — [날짜]`

---

## 출력 지시

`handover/src/03-dev-guide.md` 파일에 **Write 도구로 직접 저장**.
PROMPT_EOF

  echo "[handover-analyze] 생성: $out"
}

# ── 메인 실행 ─────────────────────────────────────────────
echo "[handover-analyze] 대상: $HANDOVER_DIR"

_gen_nex_prompt
_gen_ryn_prompt
_gen_sage_prompt
_gen_bolt_prompt

echo ""
echo "════════════════════════════════════════════════════════"
echo "[handover-analyze] 4개 prompt 생성 완료."
echo ""
echo "  $PROMPTS_DIR/00-nex.md"
echo "  $PROMPTS_DIR/01-ryn.md"
echo "  $PROMPTS_DIR/02-sage.md"
echo "  $PROMPTS_DIR/03-bolt.md"
echo ""
echo "════════════════════════════════════════════════════════"
echo "[handover-analyze] 4개 prompt 생성 완료. 메인 컨텍스트에서 Agent 4개 병렬 소환 요청:"
echo ""
echo "  Agent #1: subagent_type=architect, model=opus"
echo "            → prompt=handover/.prompts/00-nex.md"
echo "            → 텍스트 출력 (오케스트레이터가 handover/src/00-overview.md 에 Write)"
echo ""
echo "  Agent #2: subagent_type=executor, model=sonnet"
echo "            → prompt=handover/.prompts/01-ryn.md"
echo "            → Write to handover/src/01-architecture.md"
echo ""
echo "  Agent #3: subagent_type=executor, model=opus"
echo "            → prompt=handover/.prompts/02-sage.md"
echo "            → Write to handover/src/02-directory.md"
echo ""
echo "  Agent #4: subagent_type=executor, model=sonnet"
echo "            → prompt=handover/.prompts/03-bolt.md"
echo "            → Write to handover/src/03-dev-guide.md"
echo ""
echo "다음 단계:"
echo "  1. .prompts/00-nex.md ~ 03-bolt.md Read하여 prompt 내용 확인 (선택적 검수)"
echo "  2. 메인 Claude Code 컨텍스트에서 Agent 4개 병렬 소환"
echo "  3. 완료 후: bash lib/handover-render.py handover/src handover/ONBOARDING.html"
echo "════════════════════════════════════════════════════════"
