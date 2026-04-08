#!/bin/bash
# auto-growth-log.sh — 작업 완료 시 자동 growth-log 기록
# Stop/SubagentStop hook: SOUL 작업 완료 시 자동으로 성장 기록 추가

INPUT=$(cat)

# GolemGarden 환경변수 확인
GOLEM_SOUL_NAME="${GOLEM_SOUL_NAME:-}"
GOLEM_TASK="${GOLEM_TASK:-}"

# GolemGarden 작업이 아니면 패스
if [ -z "$GOLEM_SOUL_NAME" ] || [ -z "$GOLEM_TASK" ]; then
  exit 0
fi

# GOLEM_ROOT 확인
GOLEM_ROOT="${GOLEM_ROOT:-$HOME/.claude/golem-garden}"
if [ ! -f "${GOLEM_ROOT}/lib/growth-log.sh" ]; then
  exit 0
fi

# 수정된 파일 수 + 테스트 통과 수 (최선 추정)
FILES_CHANGED=$(git diff --name-only 2>/dev/null | wc -l | tr -d ' \r')
FILES_CHANGED=${FILES_CHANGED:-0}

# 결과 판정 (exit code 기반)
RESULT="${GOLEM_RESULT:-success}"

# growth-log에 기록
source "${GOLEM_ROOT}/lib/growth-log.sh"
growth_log_append "$GOLEM_SOUL_NAME" "$GOLEM_TASK" "$RESULT" "$FILES_CHANGED" 0

# 자동 승급 (rank_promote 내부에서 eligibility 검증)
source "${GOLEM_ROOT}/lib/rank-system.sh"
LOCK="/tmp/golem-promote-${GOLEM_SOUL_NAME}.lock"
if command -v flock >/dev/null 2>&1; then
  (
    flock -n 200 || exit 0
    PROMOTE_OUTPUT=$(rank_promote "$GOLEM_SOUL_NAME" 2>&1) && echo "[hook] ${PROMOTE_OUTPUT}"
  ) 200>"$LOCK"
else
  # Windows/Git Bash: flock 미지원 — 잠금 없이 직접 실행
  PROMOTE_OUTPUT=$(rank_promote "$GOLEM_SOUL_NAME" 2>&1) && echo "[hook] ${PROMOTE_OUTPUT}"
fi

exit 0
