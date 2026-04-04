#!/bin/bash
# auto-dashboard-refresh.sh — 작업 완료 시 대시보드 데이터 자동 갱신
# Stop hook: 세션 종료/작업 완료 시 dashboard/data.json 갱신

GOLEM_ROOT="${GOLEM_ROOT:-$HOME/.claude/golem-garden}"
GOLEM_DIR="${GOLEM_DIR:-${GOLEM_PROJECT:+${GOLEM_PROJECT}/.golem}}"
GOLEM_DIR="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}"

DASHBOARD_DIR="${GOLEM_DIR}/dashboard"

# 대시보드가 초기화되어 있을 때만 갱신
if [ -f "${DASHBOARD_DIR}/index.html" ]; then
  source "${GOLEM_ROOT}/lib/dashboard-web.sh" 2>/dev/null && \
    dashboard_web_refresh >/dev/null 2>&1
fi

exit 0
