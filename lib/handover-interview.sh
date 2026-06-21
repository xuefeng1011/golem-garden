#!/usr/bin/env bash
# handover-interview.sh — M2 인터뷰 Phase E: prompt 준비 + 메인 Claude 위임 메시지 출력
# Usage: bash lib/handover-interview.sh <handover_dir>
# 예:   bash lib/handover-interview.sh ./handover
#
# 규칙:
#   - set -euo pipefail
#   - sed -i 금지
#   - 모든 변수 "$VAR" 쿼팅
#   - local 의무

set -euo pipefail

# ── 인자 검증 ─────────────────────────────────────────────
if [ "$#" -lt 1 ]; then
  echo "[ERROR] Usage: bash lib/handover-interview.sh <handover_dir>" >&2
  exit 1
fi

HANDOVER_DIR="$(cd "$1" 2>/dev/null && pwd)" || {
  echo "[ERROR] handover_dir 경로를 찾을 수 없습니다: $1" >&2
  exit 1
}

# ── GOLEM_ROOT 확인 ────────────────────────────────────────
SCRIPT_PATH="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
GOLEM_ROOT="${GOLEM_ROOT:-$SCRIPT_PATH/..}"
GOLEM_ROOT="$(cd "$GOLEM_ROOT" 2>/dev/null && pwd)" || {
  echo "[ERROR] GOLEM_ROOT 경로를 찾을 수 없습니다: $GOLEM_ROOT" >&2
  exit 1
}

# ── 입력 검증: src/04-pitfalls.md, src/06-glossary.md 존재 확인 ──
_check_required_files() {
  local missing=0
  for f in "src/04-pitfalls.md" "src/06-glossary.md"; do
    if [ ! -f "$HANDOVER_DIR/$f" ]; then
      echo "[ERROR] 필수 파일이 없습니다: $HANDOVER_DIR/$f" >&2
      missing=1
    fi
  done
  if [ "$missing" -eq 1 ]; then
    echo "[안내] 먼저 handover-scan.sh를 실행하세요:" >&2
    echo "  bash lib/handover-scan.sh <project_root> $HANDOVER_DIR/src" >&2
    exit 1
  fi
}

# ── questions.md 복사/확인 ────────────────────────────────
_setup_questions() {
  local questions_dir="$HANDOVER_DIR/.questions"
  local questions_dst="$questions_dir/questions.md"
  local questions_src="$GOLEM_ROOT/handover/.questions/questions.md"

  mkdir -p "$questions_dir"

  if [ ! -f "$questions_dst" ]; then
    if [ -f "$questions_src" ]; then
      cp "$questions_src" "$questions_dst"
      echo "[handover-interview] questions.md 복사 완료: $questions_dst"
    else
      echo "[WARN] GOLEM_ROOT에 questions.md가 없습니다: $questions_src" >&2
      echo "[WARN] questions.md 없이 계속합니다." >&2
    fi
  else
    echo "[handover-interview] questions.md 이미 존재: $questions_dst"
  fi
}

# ── .interview 디렉토리 생성 ─────────────────────────────
_setup_interview_dir() {
  local interview_dir="$HANDOVER_DIR/.interview"
  mkdir -p "$interview_dir"
  echo "[handover-interview] .interview 디렉토리 준비: $interview_dir"
}

# ── 위임 메시지 출력 ──────────────────────────────────────
_print_delegation_message() {
  cat <<'DELEGATION'

══════════════════════════════════════════════════════
[handover-interview] Phase E 완료 — 메인 Claude에게 위임
══════════════════════════════════════════════════════

다음 단계 (메인 Claude 수행):

  1. handover/.questions/questions.md Read
     → 12문항 + 라운드 분할 + 매핑 섹션 확인

  2. AskUserQuestion으로 4 라운드 인터뷰 진행:
     Round 1 (워밍업, 3분): Q2 + Q8
     Round 2 (핵심, 4분): Q1 + Q3 + Q5
     Round 3 (컨벤션+온보딩, 3분): Q4 + Q6 + Q7
     Round 4 (선택, 2분): Q9 + Q10 + Q11 + Q12 (사용자가 스킵 가능)

  3. 답변 저장:
     - handover/.interview/answers.md (모든 답변 누적)

  4. 즉시 통합 (M2 스코프):
     - handover/src/04-pitfalls.md Write (Q1+Q3+Q5+Q9 통합)
     - handover/src/06-glossary.md Write (Q8 통합)

  5. M2.1에서 통합 예정 (이번엔 answers.md에만 저장):
     Q2 → 00-overview.md
     Q4, Q10 → 03-dev-guide.md
     Q6, Q12 → 07-people.md
     Q7 → 05-checklist.md
     Q11 → 01-architecture.md

  6. Phase D 재실행:
     forge handover --render-only

══════════════════════════════════════════════════════
DELEGATION
}

# ── 메인 ─────────────────────────────────────────────────
main() {
  echo "[handover-interview] Phase E 시작 — handover_dir: $HANDOVER_DIR"

  _check_required_files
  _setup_questions
  _setup_interview_dir
  _print_delegation_message
}

main
