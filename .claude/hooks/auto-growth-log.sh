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

# 랭크 체크
source "${GOLEM_ROOT}/lib/rank-system.sh"
rank_check "$GOLEM_SOUL_NAME" 2>/dev/null | grep -q "^ELIGIBLE:" && {
  echo "[hook] ${GOLEM_SOUL_NAME} 랭크 승급 가능! forge promote ${GOLEM_SOUL_NAME}으로 승급하세요."
}

exit 0
