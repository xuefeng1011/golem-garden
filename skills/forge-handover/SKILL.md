---
name: forge-handover
description: GolemGarden 프로젝트 인수인계 문서 자동 생성. 코드베이스를 스캔해 단일 HTML 핸드오버 파일을 만든다. M1은 자동 분석만 (인터뷰 없음). M2에서 인터뷰(pitfalls/glossary 보강) 추가 예정.
trigger: forge handover, 포지 인수인계, handover 만들어줘, 인수인계 자료, handover, 인수인계
---

# forge-handover — 인수인계 문서 자동 생성

사용자가 "forge handover" 또는 "인수인계 자료 만들어줘" 등을 입력하면 이 스킬이 트리거된다.

## 트리거 패턴

아래 입력은 모두 이 스킬을 실행한다:

```
forge handover
forge handover: 만들어줘
forge handover --output=./docs/handover
포지 인수인계
포지 핸드오버
handover 만들어줘
인수인계 자료 만들어줘
인수인계 문서 생성
프로젝트 핸드오버 만들어
forge handover --no-interview
```

## 동작 (M1.5 — LLM 분석 모드) ← 기본 모드

`forge handover --analyze` (또는 `forge handover`) 호출 시 4-Phase 흐름:

### Phase A — 자동 추출 (handover-scan.sh)

```bash
bash lib/handover-scan.sh <project_root> <output_dir>/src
```

raw `handover/src/*.md` 8개 생성 (00-overview ~ 07-people).

### Phase B — LLM 분석 prompt 생성 (handover-analyze.sh)

```bash
bash lib/handover-analyze.sh <output_dir>
```

`handover/.prompts/{00-nex,01-ryn,02-sage,03-bolt}.md` 4개 self-contained prompt 생성.
각 prompt는 SOUL 페르소나 + raw 입력 임베드 + 추가 컨텍스트 파일 목록 + 산출 형식 + 작성 규칙을 포함.

### Phase C — SOUL 4명 병렬 Agent 소환 (메인 컨텍스트)

**이 단계는 Bash가 직접 수행할 수 없다. 메인 Claude Code 컨텍스트가 수행.**

Phase B 완료 후 아래 출력이 표시되면, 이 스킬을 트리거한 Claude가 Agent 4개를 병렬 소환한다:

```
[handover-analyze] 4개 prompt 생성 완료. 메인 컨텍스트에서 Agent 4개 병렬 소환 요청:
  Agent #1: subagent_type=architect, model=opus → prompt=handover/.prompts/00-nex.md → 텍스트 출력
  Agent #2: subagent_type=executor,  model=sonnet → prompt=handover/.prompts/01-ryn.md  → Write to handover/src/01-architecture.md
  Agent #3: subagent_type=executor,  model=opus → prompt=handover/.prompts/02-sage.md  → Write to handover/src/02-directory.md
  Agent #4: subagent_type=executor,  model=sonnet → prompt=handover/.prompts/03-bolt.md  → Write to handover/src/03-dev-guide.md
```

스킬을 호출한 Claude는:
1. `.prompts/00-nex.md`를 Read해서 prompt 본문 추출
2. Agent 도구로 4개 병렬 호출 (subagent_type 위 매핑대로)
3. Nex 응답 텍스트를 받아 Write로 `handover/src/00-overview.md` 저장
4. Ryn/Sage/Bolt는 자기 prompt에서 Write를 직접 수행하므로 결과만 확인

### Phase D — HTML 빌드 (handover-render.py)

```bash
python lib/handover-render.py <output_dir>/src <output_dir>/ONBOARDING.html
```

M1과 동일. 분석본이 반영된 `ONBOARDING.html` 생성.

---

## 동작 (M2 — 인터뷰 모드)

`forge handover --interview` 또는 `forge handover --with-interview` 호출 시:

### Phase E — 인터뷰 prompt 준비 (handover-interview.sh)

handover/.questions/questions.md 12문항 명세 복사 + handover/.interview/ 생성 + 메인 Claude에게 위임 메시지 출력.

```bash
bash lib/handover-interview.sh <handover_dir>
```

### Phase F — AskUserQuestion 4 라운드 진행 (메인 Claude)

**이 단계는 Bash가 직접 못 함.** 메인 Claude가 수행:

1. handover/.questions/questions.md Read
2. AskUserQuestion 도구로 4 라운드 (Round 1~3 필수 + Round 4 선택)
3. 답변 → handover/.interview/answers.md 누적
4. 04-pitfalls.md, 06-glossary.md 즉시 통합 Write
5. forge handover --render-only로 HTML 재빌드

### 모드 분기

| 플래그 | 동작 |
|---|---|
| `--interview` | Phase E만 (인터뷰 prompt 생성) |
| `--with-interview` | A+B+C+D+E+F+D 풀파이프 (M2 풀버전) |
| `--analyze` (기존) | A+B+C+D (M1.5 분석만, 인터뷰 없음) |

---

## 동작 (M1 MVP — 레거시)

### 실행 흐름

```
1. bash lib/handover-scan.sh <project_root> <output_dir>/src
   → 00-overview.md ~ 07-people.md (8개 파일) 자동 생성

2. python lib/handover-render.py <output_dir>/src <output_dir>/ONBOARDING.html
   → 단일 HTML 파일 생성
```

### forge.sh 연동 (Bolt 구현)

`forge.sh` 내 `handover)` case에서 아래 형태로 호출된다:

```bash
bash "$GOLEM_ROOT/lib/handover-scan.sh" "$GOLEM_PROJECT" "$OUTPUT_DIR/src"
$PYTHON_CMD "$GOLEM_ROOT/lib/handover-render.py" "$OUTPUT_DIR/src" "$OUTPUT_DIR/ONBOARDING.html"
```

### 인자

| 인자 | 기본값 | 설명 |
|------|--------|------|
| `--output=DIR` | `./handover` | 출력 디렉토리 |
| `--scan-only`  | — | Phase A만 (M1 MVP 동작, raw 추출만) |
| `--prompts-only` | — | Phase A + B (prompt 생성까지, Agent 소환 없음) |
| `--analyze`    | (기본) | Phase A + B + C + D (M1.5 풀파이프) |
| `--render-only` | — | Phase D만 (src/*.md 있을 때 HTML만 재생성) |
| `--no-interview` | (M1에서 무시) | M2부터 유효. M1은 항상 자동 분석만 |

### 산출물

```
<output_dir>/
  src/
    00-overview.md      — 프로젝트 개요 + README 요약
    01-architecture.md  — 엔트리 포인트 + 의존성 카운트 + mermaid placeholder
    02-directory.md     — 3-depth 디렉토리 트리
    03-dev-guide.md     — 의존성 파일 + 셋업 명령
    04-pitfalls.md      — placeholder (M2 인터뷰에서 채움)
    05-checklist.md     — Day 1 / Week 1 / Month 1 체크리스트
    06-glossary.md      — placeholder (M2 인터뷰에서 채움)
    07-people.md        — git 기여자 상위 10명 + CODEOWNERS
  ONBOARDING.html       — 단일 HTML (사이드바 목차 + 각 섹션)
```

## Claude 직접 실행 방법

사용자가 `forge handover`를 요청했을 때, forge.sh 없이 Claude가 직접 실행할 경우:

### 1. 의존성 확인

```bash
# Python markdown 라이브러리 확인
python3 -c "import markdown" 2>/dev/null || echo "미설치"
```

미설치면 사용자에게 안내:
```
[안내] Python 'markdown' 라이브러리가 필요합니다.
  pip install markdown
  또는 uv pip install markdown
```

### 2. 스캔 실행

```bash
GOLEM_PROJECT="$(pwd)"
OUTPUT_DIR="./handover"
mkdir -p "$OUTPUT_DIR/src"

GOLEM_PROJECT="$GOLEM_PROJECT" bash ~/.claude/golem-garden/lib/handover-scan.sh \
  "$GOLEM_PROJECT" \
  "$OUTPUT_DIR/src"
```

### 3. HTML 렌더링

```bash
python3 ~/.claude/golem-garden/lib/handover-render.py \
  "$OUTPUT_DIR/src" \
  "$OUTPUT_DIR/ONBOARDING.html"
```

### 4. 결과 안내

```
✅ 인수인계 문서 생성 완료!

📁 출력 위치: ./handover/ONBOARDING.html
📊 섹션: 00-overview ~ 07-people (8개)

브라우저에서 열기:
  Windows: start handover/ONBOARDING.html
  macOS:   open handover/ONBOARDING.html
  Linux:   xdg-open handover/ONBOARDING.html
```

## 기능 현황

| 기능 | 상태 | 비고 |
|------|------|------|
| 자동 분석 스캔 (Phase A) | ✅ M1 | handover-scan.sh |
| LLM 분석 prompt 생성 (Phase B) | ✅ M1.5 | handover-analyze.sh |
| SOUL 4명 병렬 Agent 소환 (Phase C) | ✅ M1.5 | 메인 컨텍스트에서 수행 |
| 단일 HTML 출력 (Phase D) | ✅ M1 | handover-render.py |
| 단계별 실행 플래그 (`--scan-only` 등) | ⏳ M1.6 | forge.sh case 확장 (Bolt 구현) |
| 인터뷰 (pitfalls/glossary) | ❌ M2 | — |
| mermaid 아키텍처 다이어그램 | ❌ M3 | — |
| 검색 기능 (Ctrl+K) | ❌ M3 | — |
| 코드 링크 (파일 → GitHub) | ❌ M3 | — |
| 다크모드 | ❌ M3 | — |

## 의존성

### Python 라이브러리

```
markdown>=3.0
```

설치 방법:
```bash
pip install markdown
# 또는
uv pip install markdown
# 또는 (가상환경 내)
uv add markdown
```

### 시스템 명령

- `git` — 기여자 분석 (07-people.md). 없어도 나머지는 정상 동작.
- `python3` — HTML 렌더링 필수.
- `find`, `grep`, `sort`, `uniq` — 스캔 (Git Bash / Linux / macOS 공통).

## 오류 처리

| 상황 | 동작 |
|------|------|
| markdown 미설치 | stderr 안내 출력 후 exit 1 |
| git 없음/실패 | 07-people.md만 빈 상태, 나머지 정상 생성 |
| README 없음 | "_(없음)_" 표시 |
| src_dir MD 파일 없음 | 경고 출력 후 빈 HTML 생성 |

---

💡 다음 작업:
  • `forge build: {작업}` — 인수인계 문서 기반으로 작업 시작
  • `forge status` — 팀 현황 확인
  • `forge review` — 생성된 문서 품질 검토
