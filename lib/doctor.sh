#!/bin/bash
# doctor.sh — GolemGarden 엔진 상태 진단 (read-only, no state writes)
# Usage: source lib/doctor.sh && doctor_run [--verbose]
#
# 체크리스트:
#   CRITICAL: claude CLI, GOLEM_ROOT libs sourceable, soul parse, bash version
#   WARNINGS: .golem/ 존재, 선택 도구, 쓰기 권한, OMC 잔재
#
# 출력 형식:
#   ✓ 이름 — 상세
#   ✗ 이름 — 상세 (CRITICAL 실패)
#   ⚠ 이름 — 상세 (경고)
#
# 종료 코드: 0 = CRITICAL 전부 통과, 1 = CRITICAL 실패 있음

# GOLEM_ROOT 결정 — 단독 source 시에도 동작
_DR_ROOT="${GOLEM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# ─────────────────────────────────────────────────────────
# 내부 헬퍼
# ─────────────────────────────────────────────────────────

_dr_pass()  { printf '  \033[32m✓\033[0m %s\n' "$*"; }
_dr_fail()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }
_dr_warn()  { printf '  \033[33m⚠\033[0m %s\n' "$*"; }
_dr_head()  { printf '\n\033[1m%s\033[0m\n' "$*"; }

# ─────────────────────────────────────────────────────────
# doctor_run — 메인 진단 함수
# ─────────────────────────────────────────────────────────
doctor_run() {
  local verbose=0
  [ "${1:-}" = "--verbose" ] && verbose=1

  local pass=0 warn=0 fail=0

  printf '\033[1mGolemGarden Engine Doctor\033[0m\n'
  printf '진단 경로: %s\n' "${_DR_ROOT}"

  # ══════════════════════════════════════════════════════
  # CORE — CRITICAL 체크
  # ══════════════════════════════════════════════════════
  _dr_head "[CORE] 엔진 핵심 의존성"

  # 1. claude CLI on PATH
  local claude_path claude_ver
  claude_path=$(command -v claude 2>/dev/null)
  if [ -n "$claude_path" ]; then
    # --version 이 stderr 로 나올 수도 있으므로 합쳐서 캡처
    claude_ver=$(claude --version 2>&1 | head -1)
    _dr_pass "claude CLI — ${claude_ver} (${claude_path})"
    pass=$((pass+1))
  else
    _dr_fail "claude CLI — PATH에 없음. 설치 후 재시도하세요."
    fail=$((fail+1))
  fi

  # 2. GOLEM_ROOT 존재 여부
  if [ -d "${_DR_ROOT}" ]; then
    _dr_pass "GOLEM_ROOT — ${_DR_ROOT}"
    pass=$((pass+1))
  else
    _dr_fail "GOLEM_ROOT — 디렉토리 없음: ${_DR_ROOT}"
    fail=$((fail+1))
  fi

  # 3. 핵심 라이브러리 존재 + 구문 검사
  local core_libs="soul-parser.sh agent-runner.sh prompt-builder.sh growth-log.sh session.sh budget.sh"
  local lib_ok=1
  for lib in $core_libs; do
    local lib_path="${_DR_ROOT}/lib/${lib}"
    if [ ! -f "$lib_path" ]; then
      _dr_fail "lib/${lib} — 파일 없음"
      fail=$((fail+1))
      lib_ok=0
      continue
    fi
    # bash -n : 구문 오류만 체크 (실행 안 함)
    local syntax_out syntax_ok
    syntax_out=$(bash -n "$lib_path" 2>&1); syntax_ok=$?
    if [ "$syntax_ok" -eq 0 ]; then
      [ "$verbose" = "1" ] && _dr_pass "lib/${lib} — 구문 OK"
      pass=$((pass+1))
    else
      _dr_fail "lib/${lib} — 구문 오류: ${syntax_out}"
      fail=$((fail+1))
      lib_ok=0
    fi
  done
  # 라이브러리 전부 통과 시 요약 1줄 (non-verbose)
  if [ "$verbose" = "0" ] && [ "$lib_ok" = "1" ]; then
    _dr_pass "핵심 라이브러리 (6개) — 모두 구문 OK"
    # pass는 개별 카운트했으므로 여기서 추가 안 함
  fi

  # 4. SOUL 파싱 테스트 (nex 또는 첫 번째 souls/*.md)
  local test_soul=""
  local souls_dir="${_DR_ROOT}/souls"
  if [ -f "${souls_dir}/nex.md" ]; then
    test_soul="nex"
  else
    # glob 결과를 POSIX 방식으로 첫 번째 파일 선택
    for f in "${souls_dir}"/*.md; do
      [ -f "$f" ] && test_soul="$(basename "$f" .md)" && break
    done
  fi

  if [ -z "$test_soul" ]; then
    _dr_fail "SOUL 파싱 — souls/ 에 .md 파일 없음"
    fail=$((fail+1))
  else
    # 서브셸에서 source 후 soul_parse 실행 (현재 셸 오염 방지)
    # SC2030/SC2031: 의도적 서브셸 격리 — export는 서브셸 내에서만 유효해야 함
    local parse_out
    parse_out=$(
      export GOLEM_ROOT="${_DR_ROOT}"
      # shellcheck disable=SC2030
      export GOLEM_DIR="${GOLEM_DIR:-${_DR_ROOT}/.golem}"
      # shellcheck disable=SC2030
      export GOLEM_PROJECT="${GOLEM_PROJECT:-${_DR_ROOT}}"
      # shellcheck disable=SC1091
      source "${_DR_ROOT}/lib/soul-parser.sh" 2>/dev/null
      soul_file=$(_resolve_soul_file "$test_soul" 2>/dev/null)
      if [ -z "$soul_file" ]; then
        echo "NOTFOUND"
      else
        soul_parse "$soul_file" 2>/dev/null
        echo "PARSED"
      fi
    )
    if echo "$parse_out" | grep -q "PARSED"; then
      _dr_pass "SOUL 파싱 — ${test_soul}.md 정상 파싱"
      pass=$((pass+1))
    else
      _dr_fail "SOUL 파싱 — ${test_soul} 파싱 실패 (soul_parse 오류)"
      fail=$((fail+1))
    fi
  fi

  # 5. bash 버전 ≥ 3.2 (연관 배열 등)
  local bash_ver bash_major bash_minor
  bash_ver="${BASH_VERSION:-unknown}"
  bash_major=$(echo "$bash_ver" | cut -d. -f1)
  bash_minor=$(echo "$bash_ver" | cut -d. -f2)
  if [ "${bash_major:-0}" -gt 3 ] || { [ "${bash_major:-0}" -eq 3 ] && [ "${bash_minor:-0}" -ge 2 ]; }; then
    _dr_pass "bash 버전 — ${bash_ver} (≥ 3.2 필요)"
    pass=$((pass+1))
  else
    _dr_fail "bash 버전 — ${bash_ver} (3.2 미만: 연관 배열 등 미지원)"
    fail=$((fail+1))
  fi

  # ══════════════════════════════════════════════════════
  # DEPENDENCIES — 선택 도구 경고
  # ══════════════════════════════════════════════════════
  _dr_head "[DEPENDENCIES] 선택 도구"

  # 린터: shellcheck
  if command -v shellcheck >/dev/null 2>&1; then
    local sc_ver
    sc_ver=$(shellcheck --version 2>/dev/null | grep 'version:' | awk '{print $2}')
    _dr_pass "shellcheck — ${sc_ver:-설치됨}"
    pass=$((pass+1))
  else
    _dr_warn "shellcheck — 미설치 (스크립트 린트 불가)"
    warn=$((warn+1))
  fi

  # bats (테스트)
  if command -v bats >/dev/null 2>&1; then
    local bats_ver
    bats_ver=$(bats --version 2>/dev/null | head -1)
    _dr_pass "bats — ${bats_ver:-설치됨}"
    pass=$((pass+1))
  else
    _dr_warn "bats — 미설치 (tests/bats/ 단위 테스트 실행 불가)"
    warn=$((warn+1))
  fi

  # timeout / gtimeout (runaway 보호 의존성)
  if command -v timeout >/dev/null 2>&1; then
    _dr_pass "timeout — $(command -v timeout)"
    pass=$((pass+1))
  elif command -v gtimeout >/dev/null 2>&1; then
    _dr_pass "gtimeout (GNU coreutils) — $(command -v gtimeout)"
    pass=$((pass+1))
  else
    _dr_warn "timeout/gtimeout — 미설치 (에이전트 폭주 보호 비활성화됨)"
    warn=$((warn+1))
  fi

  # python3 (UUID 생성 등 — Windows 스텁 감지)
  local py_cmd py_real=0
  py_cmd=$(command -v python3 2>/dev/null || command -v python 2>/dev/null)
  if [ -n "$py_cmd" ]; then
    # 실제 실행 가능한지 확인 (WindowsApps 스텁은 uuid import 실패)
    if "$py_cmd" -c "import uuid; print(uuid.uuid4())" >/dev/null 2>&1; then
      local py_ver
      py_ver=$("$py_cmd" --version 2>&1 | head -1)
      _dr_pass "python3 — ${py_ver} (${py_cmd})"
      py_real=1
      pass=$((pass+1))
    else
      _dr_warn "python3 — WindowsApps 스텁 감지됨 (실제 Python 없음). UUID 생성은 /proc 폴백 사용."
      warn=$((warn+1))
    fi
  else
    _dr_warn "python3/python — 미설치 (UUID 생성은 /dev/urandom 폴백)"
    warn=$((warn+1))
  fi
  # py_real 사용 억제 (향후 확장용)
  : "${py_real}"

  # rg / ripgrep
  if command -v rg >/dev/null 2>&1; then
    local rg_ver
    rg_ver=$(rg --version 2>/dev/null | head -1)
    _dr_pass "rg (ripgrep) — ${rg_ver}"
    pass=$((pass+1))
  else
    _dr_warn "rg (ripgrep) — 미설치 (코드 검색 성능 저하)"
    warn=$((warn+1))
  fi

  # ══════════════════════════════════════════════════════
  # PROJECT — 프로젝트별 경고
  # ══════════════════════════════════════════════════════
  _dr_head "[PROJECT] 프로젝트 상태"

  # .golem/ 존재 여부
  # shellcheck disable=SC2031
  local project_golem="${GOLEM_DIR:-${GOLEM_PROJECT:-$(pwd)}/.golem}"
  if [ -d "$project_golem" ]; then
    _dr_pass ".golem/ — ${project_golem}"
    pass=$((pass+1))
  else
    _dr_warn ".golem/ — 없음 (forge-init 실행 권장): ${project_golem}"
    warn=$((warn+1))
  fi

  # growth-log 쓰기 가능
  local growth_dir="${project_golem}/growth-log"
  if [ -d "$growth_dir" ]; then
    if [ -w "$growth_dir" ]; then
      _dr_pass "growth-log/ — 쓰기 가능"
      pass=$((pass+1))
    else
      _dr_warn "growth-log/ — 쓰기 불가 (성장 기록 저장 실패 가능)"
      warn=$((warn+1))
    fi
  else
    _dr_warn "growth-log/ — 디렉토리 없음 (forge-init 실행 권장)"
    warn=$((warn+1))
  fi

  # sessions/ 쓰기 가능 (있는 경우)
  local sessions_dir="${project_golem}/sessions"
  if [ -d "$sessions_dir" ]; then
    if [ -w "$sessions_dir" ]; then
      _dr_pass "sessions/ — 쓰기 가능"
      pass=$((pass+1))
    else
      _dr_warn "sessions/ — 쓰기 불가 (세션 지속성 저장 실패 가능)"
      warn=$((warn+1))
    fi
  fi

  # missions/ 쓰기 가능 (있는 경우)
  local missions_dir="${project_golem}/missions"
  if [ -d "$missions_dir" ]; then
    if [ -w "$missions_dir" ]; then
      _dr_pass "missions/ — 쓰기 가능"
      pass=$((pass+1))
    else
      _dr_warn "missions/ — 쓰기 불가 (미션 추적 저장 실패 가능)"
      warn=$((warn+1))
    fi
  fi

  # OMC 잔재 확인: .claude/settings.json 에 oh-my-claudecode 플러그인 선언 여부
  # shellcheck disable=SC2031
  local settings_file="${GOLEM_PROJECT:-$(pwd)}/.claude/settings.json"
  if [ -f "$settings_file" ]; then
    if grep -q "oh-my-claudecode" "$settings_file" 2>/dev/null; then
      _dr_warn "OMC 잔재 — ${settings_file} 에 oh-my-claudecode 플러그인 선언 감지. 엔진 혼선 가능."
      warn=$((warn+1))
    else
      _dr_pass "OMC 잔재 없음 — settings.json 클린"
      pass=$((pass+1))
    fi
  else
    _dr_pass "OMC 잔재 없음 — settings.json 없거나 플러그인 선언 없음"
    pass=$((pass+1))
  fi

  # ══════════════════════════════════════════════════════
  # 요약
  # ══════════════════════════════════════════════════════
  printf '\n%s\n' "──────────────────────────────────────────────"
  printf '진단 결과: \033[32m%d개 통과\033[0m, \033[33m%d개 경고\033[0m, \033[31m%d개 실패\033[0m\n' \
    "$pass" "$warn" "$fail"

  if [ "$fail" -gt 0 ]; then
    printf '\033[31m엔진 실행 불가\033[0m — CRITICAL 항목을 먼저 해결하세요.\n'
    printf '(exit 1)\n'
    return 1
  else
    printf '\033[32m엔진 정상\033[0m — 모든 CRITICAL 체크 통과.\n'
    if [ "$warn" -gt 0 ]; then
      printf '선택 도구 일부 없음 (위 ⚠ 항목). 기능 저하 없이 실행 가능.\n'
    fi
    printf '(exit 0)\n'
    return 0
  fi
}
