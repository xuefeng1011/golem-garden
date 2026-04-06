#!/bin/bash
# auto-dashboard-refresh.sh — 작업 완료 시 대시보드 데이터 자동 갱신
# Stop hook: 세션 종료/작업 완료 시 dashboard/data.json 갱신

GOLEM_ROOT="${GOLEM_ROOT:-$HOME/.claude/golem-garden}"

# 현재 작업 디렉토리에서 프로젝트 감지
if [ -z "${GOLEM_PROJECT:-}" ]; then
  if [ -d "$(pwd)/.golem" ]; then
    GOLEM_PROJECT="$(pwd)"
  fi
fi
export GOLEM_PROJECT

GOLEM_DIR="${GOLEM_DIR:-${GOLEM_PROJECT:+${GOLEM_PROJECT}/.golem}}"
GOLEM_DIR="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}"

DASHBOARD_DIR="${GOLEM_DIR}/dashboard"

# 프로젝트 대시보드 갱신
if [ -f "${DASHBOARD_DIR}/index.html" ]; then
  source "${GOLEM_ROOT}/lib/dashboard-web.sh" 2>/dev/null && \
    dashboard_web_refresh >/dev/null 2>&1
fi

# 글로벌 대시보드: 프로젝트 등록 + 데이터 갱신
GLOBAL_DASHBOARD="${GOLEM_ROOT}/dashboard"
if [ -f "${GOLEM_ROOT}/lib/dashboard-global.sh" ]; then
  source "${GOLEM_ROOT}/lib/dashboard-global.sh" 2>/dev/null
  # 프로젝트 등록 (HTML 존재 여부와 무관하게 항상)
  if [ -n "${GOLEM_PROJECT:-}" ] && [ -d "${GOLEM_PROJECT}/.golem" ]; then
    dashboard_global_register "$GOLEM_PROJECT" >/dev/null 2>&1
  fi
  # 대시보드 데이터 갱신 (HTML 있을 때만)
  if [ -f "${GLOBAL_DASHBOARD}/index.html" ]; then
    dashboard_global_refresh >/dev/null 2>&1
  fi
fi

exit 0
