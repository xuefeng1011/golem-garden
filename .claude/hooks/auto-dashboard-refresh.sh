#!/bin/bash
# auto-dashboard-refresh.sh — 작업 완료 시 대시보드 데이터 자동 갱신
# Stop hook: 세션 종료/작업 완료 시 dashboard/data.json 갱신

GOLEM_ROOT="${GOLEM_ROOT:-$HOME/.claude/golem-garden}"
GOLEM_DIR="${GOLEM_DIR:-${GOLEM_PROJECT:+${GOLEM_PROJECT}/.golem}}"
GOLEM_DIR="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}"

DASHBOARD_DIR="${GOLEM_DIR}/dashboard"

# 프로젝트 대시보드 갱신
if [ -f "${DASHBOARD_DIR}/index.html" ]; then
  source "${GOLEM_ROOT}/lib/dashboard-web.sh" 2>/dev/null && \
    dashboard_web_refresh >/dev/null 2>&1
fi

# 글로벌 대시보드 갱신
GLOBAL_DASHBOARD="${GOLEM_ROOT}/dashboard"
if [ -f "${GLOBAL_DASHBOARD}/index.html" ]; then
  source "${GOLEM_ROOT}/lib/dashboard-global.sh" 2>/dev/null && \
    dashboard_global_refresh >/dev/null 2>&1
fi

exit 0
