#!/bin/bash
# verify.sh — 검증 레인 (결정론적 테스트 + 독립 SOUL 심판)
# Usage: source lib/verify.sh && verify_run "AuthController 구현 완료" [verifier_soul]
#        source lib/verify.sh && verify_tests_only
#
# 설계 원칙: author≠verifier (저자가 스스로 검증하는 것 금지)
# 환경변수:
#   VERIFY_AUTHOR_SOUL   — 작업을 수행한 SOUL 이름 (가드용)
#   GOLEM_VERIFY_TMPDIR  — bats 실행용 TMPDIR 오버라이드 (Windows 대응)
#   VERIFY_TESTS_ONLY    — "1" 이면 SOUL 호출 없이 테스트만 실행

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# GOLEM_DIR 정규화 — agent-runner.sh 패턴 미러
case "${GOLEM_DIR:-}" in
  */.golem) : ;;
  *)
    if [ -n "${GOLEM_PROJECT:-}" ]; then
      GOLEM_DIR="${GOLEM_PROJECT}/.golem"
    elif [ -d "$(pwd)/.golem" ]; then
      GOLEM_DIR="$(pwd)/.golem"
    else
      GOLEM_DIR="${GOLEM_ROOT}/.golem"
    fi
    ;;
esac

# ─────────────────────────────────────────────────────────
# 내부 헬퍼
# ─────────────────────────────────────────────────────────

# 결과 블록 출력 (stdout)
_verify_print_block() {
  local target="$1"
  local test_status="$2"   # PASS | FAIL | SKIP
  local test_summary="$3"
  local soul_verdict="$4"  # PASS | FAIL | SKIP(tests-only)
  local soul_reason="$5"
  local overall="$6"       # PASS | FAIL

  echo ""
  echo "╔══════════════════════════════════════════════════╗"
  echo "║               VERIFY VERDICT                    ║"
  echo "╠══════════════════════════════════════════════════╣"
  printf "║  대상: %-42s║\n" "$target"
  echo "╠══════════════════════════════════════════════════╣"
  printf "║  [결정론적] 테스트: %-29s║\n" "$test_status"
  printf "║    %s\n" "$test_summary" | head -3
  echo "╠══════════════════════════════════════════════════╣"
  printf "║  [SOUL 심판] %s: %-32s║\n" "${VERIFY_SOUL_NAME:-verifier}" "$soul_verdict"
  if [ -n "$soul_reason" ]; then
    printf "║    %s\n" "$soul_reason" | head -2
  fi
  echo "╠══════════════════════════════════════════════════╣"
  printf "║  최종 판정: %-37s║\n" "$overall"
  echo "╚══════════════════════════════════════════════════╝"
  echo ""
}

# 테스트 러너 감지 및 실행
# stdout: "PASS <counts>" | "FAIL <counts>" | "SKIP no-runner"
# return: 0=pass, 1=fail, 2=skip(no runner)
_verify_run_tests() {
  local proj="${GOLEM_PROJECT:-$(pwd)}"
  local bats_runner="${proj}/tests/bats/run.sh"
  local pkg_json="${proj}/package.json"
  local pytest_ini="${proj}/pytest.ini"
  local pyproject="${proj}/pyproject.toml"

  # ① bats — 이 프로젝트의 주 테스트 수단
  if [ -f "$bats_runner" ]; then
    local tmp_out
    tmp_out=$(mktemp 2>/dev/null)
    if [ -z "$tmp_out" ]; then
      tmp_out="${GOLEM_VERIFY_TMPDIR:-/c/tmp/golem-bats}/verify_bats_$$"
      mkdir -p "$(dirname "$tmp_out")" 2>/dev/null
      : > "$tmp_out"
    fi
    local bats_rc=0
    # Windows TMPDIR 워크어라운드 (run.sh 와 동일)
    TMPDIR="${GOLEM_VERIFY_TMPDIR:-/c/tmp/golem-bats}" \
    BATS_TMPDIR="${GOLEM_VERIFY_TMPDIR:-/c/tmp/golem-bats}" \
      bash "$bats_runner" >"$tmp_out" 2>&1 || bats_rc=$?

    # bats 출력에서 "ok N" / "not ok N" 카운트 파싱 (Windows CRLF 대응)
    local total fail pass
    total=$(grep -cE '^(ok|not ok) ' "$tmp_out" 2>/dev/null | tr -d '[:space:]')
    fail=$(grep -c '^not ok' "$tmp_out" 2>/dev/null | tr -d '[:space:]')
    total=${total:-0}; fail=${fail:-0}
    # 숫자가 아니면 0으로 정규화 (mktemp 실패 등 예외 대응)
    printf '%s' "$total" | grep -qE '^[0-9]+$' || total=0
    printf '%s' "$fail"  | grep -qE '^[0-9]+$' || fail=0
    pass=$(( total - fail ))
    local summary="${total}개 중 ${pass}개 통과, ${fail}개 실패"

    if [ "$bats_rc" -eq 0 ] && [ "$fail" -eq 0 ]; then
      printf 'PASS %s' "$summary"
      rm -f "$tmp_out"
      return 0
    else
      # 실패 시 마지막 10줄 요약 추가
      local tail_out
      tail_out=$(tail -10 "$tmp_out" 2>/dev/null | tr '\n' '|')
      printf 'FAIL %s | %s' "$summary" "$tail_out"
      rm -f "$tmp_out"
      return 1
    fi
  fi

  # ② npm test
  if [ -f "$pkg_json" ] && grep -q '"test"' "$pkg_json" 2>/dev/null; then
    local tmp_out
    tmp_out=$(mktemp 2>/dev/null || echo "/tmp/verify_npm_$$")
    local npm_rc=0
    ( cd "$proj" && npm test --silent 2>&1 ) >"$tmp_out" || npm_rc=$?
    local summary
    summary=$(tail -5 "$tmp_out" 2>/dev/null | tr '\n' ' ')
    rm -f "$tmp_out"
    if [ "$npm_rc" -eq 0 ]; then
      printf 'PASS npm test 통과 | %s' "$summary"
      return 0
    else
      printf 'FAIL npm test 실패 | %s' "$summary"
      return 1
    fi
  fi

  # ③ pytest
  if [ -f "$pytest_ini" ] || ([ -f "$pyproject" ] && grep -q 'pytest' "$pyproject" 2>/dev/null); then
    local tmp_out
    tmp_out=$(mktemp 2>/dev/null || echo "/tmp/verify_pytest_$$")
    local pytest_rc=0
    ( cd "$proj" && python -m pytest -q 2>&1 ) >"$tmp_out" || pytest_rc=$?
    local summary
    summary=$(tail -3 "$tmp_out" 2>/dev/null | tr '\n' ' ')
    rm -f "$tmp_out"
    if [ "$pytest_rc" -eq 0 ]; then
      printf 'PASS pytest 통과 | %s' "$summary"
      return 0
    else
      printf 'FAIL pytest 실패 | %s' "$summary"
      return 1
    fi
  fi

  # ④ 러너 없음 — 소프트 스킵 (FAIL 이 아님)
  printf 'SKIP 테스트 러너 감지 불가 (bats/npm/pytest 없음)'
  return 2
}

# ─────────────────────────────────────────────────────────
# 공개 함수: verify_tests_only
# ─────────────────────────────────────────────────────────
# 결정론적 테스트만 실행. SOUL 호출 없이 CI 스타일로 빠르게 검증.
# return: 0=pass, 1=fail, 2=skip
verify_tests_only() {
  echo "[verify] 결정론적 검증 시작..."
  local result
  result=$(_verify_run_tests)
  local rc=$?

  local detail="${result#* }"

  case "$rc" in
    0) echo "[verify] PASS — $detail" ;;
    1) echo "[verify] FAIL — $detail" ;;
    2) echo "[verify] SKIP — $detail" ;;
  esac

  return $rc
}

# ─────────────────────────────────────────────────────────
# 공개 함수: verify_run
# ─────────────────────────────────────────────────────────
# verify_run <target_description> [verifier_soul]
#
# 1. 결정론적 테스트 실행 (AUTHORITATIVE — 실패 시 전체 FAIL)
# 2. 독립 SOUL 심판 (author≠verifier 가드)
# 3. 결합 판정 출력 + return 0/1
#
# --tests-only 또는 VERIFY_TESTS_ONLY=1: SOUL 호출 생략
verify_run() {
  local target=""
  local verifier_soul="zen"
  local tests_only=0

  # 첫 번째 위치 인자는 항상 target (빈 문자열도 그대로 받음)
  # — for 루프 방식은 빈 첫 인자를 건너뛰고 다음 인자가 target 을 덮어써
  #   "verify_run '' zen" 이 target=zen 으로 둔갑하는 버그가 있었다.
  if [ $# -ge 1 ]; then
    target="$1"
    shift
  fi

  # 나머지 인자에서 --tests-only 와 verifier_soul 파싱
  for arg in "$@"; do
    case "$arg" in
      --tests-only) tests_only=1 ;;
      *)
        if [ "$verifier_soul" = "zen" ]; then
          verifier_soul="$arg"
        fi
        ;;
    esac
  done

  [ "${VERIFY_TESTS_ONLY:-0}" = "1" ] && tests_only=1

  if [ -z "$target" ]; then
    echo "[verify] Usage: verify_run <target_description> [verifier_soul] [--tests-only]" >&2
    return 1
  fi

  # ── author≠verifier 가드 ──────────────────────────────
  # VERIFY_AUTHOR_SOUL 이 설정돼 있고 verifier_soul 과 동일하면 차단.
  # (소문자 정규화로 비교 — Zen vs zen 허용 안 함)
  if [ -n "${VERIFY_AUTHOR_SOUL:-}" ]; then
    local _author_lc _verifier_lc
    _author_lc=$(printf '%s' "$VERIFY_AUTHOR_SOUL" | tr '[:upper:]' '[:lower:]')
    _verifier_lc=$(printf '%s' "$verifier_soul" | tr '[:upper:]' '[:lower:]')
    if [ "$_author_lc" = "$_verifier_lc" ]; then
      echo "[verify] ERROR: author≠verifier 위반 — '${VERIFY_AUTHOR_SOUL}'는 자신의 작업을 검증할 수 없습니다." >&2
      echo "[verify]   다른 SOUL을 verifier_soul 로 지정하거나 VERIFY_AUTHOR_SOUL 을 해제하세요." >&2
      return 1
    fi
  fi

  echo "[verify] ========================================"
  echo "[verify] 대상: $target"
  echo "[verify] 검증자: ${verifier_soul}"
  [ -n "${VERIFY_AUTHOR_SOUL:-}" ] && echo "[verify] 작업자(저자): ${VERIFY_AUTHOR_SOUL}"
  echo "[verify] ========================================"

  # ── Step 1: 결정론적 테스트 ──────────────────────────
  echo "[verify] [1/2] 결정론적 테스트 실행 중..."
  local test_result
  test_result=$(_verify_run_tests)
  local test_rc=$?

  local test_status="${test_result%% *}"
  local test_detail="${test_result#* }"

  echo "[verify] 테스트 결과: $test_status — $test_detail"

  # 테스트 실패 → 즉시 FAIL (SOUL 심판 없이)
  if [ "$test_rc" -eq 1 ]; then
    echo "[verify] 테스트 실패 — SOUL 심판 생략 (결정론적 결과 우선)"
    _verify_print_block "$target" "FAIL" "$test_detail" "SKIP(테스트실패로생략)" "" "FAIL"
    return 1
  fi

  # ── Step 2: SOUL 심판 ─────────────────────────────────
  local soul_verdict="SKIP"
  local soul_reason=""
  VERIFY_SOUL_NAME="$verifier_soul"

  if [ "$tests_only" -eq 1 ]; then
    soul_verdict="SKIP(--tests-only)"
    soul_reason="SOUL 호출 생략 (--tests-only 모드)"
    echo "[verify] [2/2] SOUL 심판 생략 (--tests-only)"
  else
    # agent-runner.sh 가 아직 source 되지 않았을 수 있음
    if ! command -v agent_run >/dev/null 2>&1; then
      source "${GOLEM_ROOT}/lib/agent-runner.sh" 2>/dev/null
    fi

    if ! command -v agent_run >/dev/null 2>&1; then
      echo "[verify] WARNING: agent-runner.sh 로드 실패 — SOUL 심판 생략" >&2
      soul_verdict="SKIP(agent-runner미로드)"
      soul_reason="agent-runner.sh를 source할 수 없어 SOUL 심판을 건너뜁니다."
    else
      echo "[verify] [2/2] ${verifier_soul} SOUL 심판 호출 중..."

      local verifier_prompt
      verifier_prompt="당신은 독립적인 검증자입니다. 저자와 다른 SOUL로서 아래 작업 결과를 공정하게 심판하세요.

검증 대상: ${target}

테스트 결과: ${test_status}
  ${test_detail}

위 정보를 바탕으로:
1. 코드/작업의 완성도를 독립적으로 평가하세요
2. 테스트가 충분히 신뢰할 만한지 판단하세요
3. 최종 판정을 첫 줄에 반드시 'PASS' 또는 'FAIL' 로 명시하세요
4. 이유를 2-3문장으로 설명하세요

형식:
PASS 또는 FAIL
이유: ..."

      local soul_output
      soul_output=$(agent_run "$verifier_soul" "$verifier_prompt" 2>/dev/null)
      local agent_rc=$?

      if [ "$agent_rc" -ne 0 ] || [ -z "$soul_output" ]; then
        echo "[verify] WARNING: SOUL 심판 실패 (agent_run rc=${agent_rc})" >&2
        soul_verdict="SKIP(SOUL호출실패)"
        soul_reason="agent_run 오류 또는 빈 응답"
      else
        # PASS/FAIL 파싱 — 첫 줄 우선, 없으면 전체 스캔
        local _first_line
        _first_line=$(printf '%s' "$soul_output" | head -1)
        if printf '%s' "$_first_line" | grep -iqE '\bPASS\b'; then
          soul_verdict="PASS"
        elif printf '%s' "$_first_line" | grep -iqE '\bFAIL\b'; then
          soul_verdict="FAIL"
        elif printf '%s' "$soul_output" | grep -iqE '\bPASS\b'; then
          soul_verdict="PASS"
        elif printf '%s' "$soul_output" | grep -iqE '\bFAIL\b'; then
          soul_verdict="FAIL"
        else
          soul_verdict="SKIP(판정불명확)"
        fi
        # 첫 3줄을 이유로
        soul_reason=$(printf '%s' "$soul_output" | head -3 | tr '\n' ' ')
      fi
    fi
  fi

  # ── Step 3: 결합 판정 ────────────────────────────────
  # 전체 PASS 조건: (테스트 pass 또는 skip) AND (SOUL PASS 또는 SOUL skip)
  local overall="FAIL"
  local test_ok=0
  local soul_ok=0

  { [ "$test_rc" -eq 0 ] || [ "$test_rc" -eq 2 ]; } && test_ok=1
  case "$soul_verdict" in
    PASS)                soul_ok=1 ;;
    SKIP*|"--tests-only") soul_ok=1 ;;  # SOUL 생략 = 테스트 결과 신뢰
  esac

  [ "$test_ok" -eq 1 ] && [ "$soul_ok" -eq 1 ] && overall="PASS"

  _verify_print_block "$target" "$test_status" "$test_detail" "$soul_verdict" "$soul_reason" "$overall"

  [ "$overall" = "PASS" ] && return 0 || return 1
}
