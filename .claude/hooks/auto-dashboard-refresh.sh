#!/usr/bin/env bash
# auto-dashboard-refresh.sh — 작업 완료 시 대시보드 데이터 자동 갱신
# Stop hook: 세션 종료/작업 완료 시 dashboard/data.json 갱신
# NOTE: 쿨다운 + 백그라운드 + timeout(settings.json)으로 블로킹 방지

GOLEM_ROOT="${GOLEM_ROOT:-$HOME/.claude/golem-garden}"

# 쿨다운: 마지막 갱신 후 120초 이내면 즉시 스킵
COOLDOWN_FILE="${GOLEM_ROOT}/dashboard/.last-refresh"
if [ -f "$COOLDOWN_FILE" ]; then
  last=$(cat "$COOLDOWN_FILE" 2>/dev/null | tr -d '\r\n')
  now=$(date +%s)
  elapsed=$(( now - last ))
  if [ "$elapsed" -lt 120 ] 2>/dev/null; then
    exit 0
  fi
fi

# 쿨다운 타임스탬프 즉시 기록 (다음 호출이 스킵되도록 — 백그라운드 전에 기록)
mkdir -p "${GOLEM_ROOT}/dashboard"
date +%s > "$COOLDOWN_FILE"

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
GLOBAL_DASHBOARD="${GOLEM_ROOT}/dashboard"

# 프로젝트 등록 (가벼운 작업 — 동기 실행)
if [ -f "${GOLEM_ROOT}/lib/dashboard-global.sh" ]; then
  source "${GOLEM_ROOT}/lib/dashboard-global.sh" 2>/dev/null
  if [ -n "${GOLEM_PROJECT:-}" ] && [ -d "${GOLEM_PROJECT}/.golem" ]; then
    dashboard_global_register "$GOLEM_PROJECT" >/dev/null 2>&1
  fi
fi

# 무거운 refresh를 별도 프로세스로 detach (stdin/stdout/stderr 닫아서 완전 분리)
bash -c "
  GOLEM_ROOT='${GOLEM_ROOT}'
  GOLEM_PROJECT='${GOLEM_PROJECT:-}'
  GOLEM_DIR='${GOLEM_DIR}'
  DASHBOARD_DIR='${DASHBOARD_DIR}'
  GLOBAL_DASHBOARD='${GLOBAL_DASHBOARD}'

  # 프로젝트 대시보드 갱신
  if [ -f \"\${DASHBOARD_DIR}/index.html\" ]; then
    source \"\${GOLEM_ROOT}/lib/dashboard-web.sh\" 2>/dev/null && \
      dashboard_web_refresh >/dev/null 2>&1
  fi

  # 글로벌 대시보드 데이터 갱신
  if [ -f \"\${GLOBAL_DASHBOARD}/index.html\" ] && [ -f \"\${GOLEM_ROOT}/lib/dashboard-global.sh\" ]; then
    source \"\${GOLEM_ROOT}/lib/dashboard-global.sh\" 2>/dev/null
    dashboard_global_refresh >/dev/null 2>&1
  fi
" </dev/null >/dev/null 2>&1 &
disown 2>/dev/null

exit 0
