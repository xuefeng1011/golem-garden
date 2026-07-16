#!/usr/bin/env bash
# env-probe.sh — 환경 실측 후 ${GOLEM_DIR}/env.md 생성 (P0-2)
# 목적: "테스트는 TMPDIR=C:/tmp 로", "uv 없으니 venv python 으로" 같은
# 환경 사실을 매 SOUL 프롬프트마다 수동 주입하던 것을 엔진이 자동화.
# Usage: source lib/env-probe.sh && env_probe_generate
#
# doctor.sh 의 체크(사람용 출력)를 파싱하지 않고 동일한 원시 검사
# (command -v, 파일 존재)를 직접 재실행한다 — 단순함 우선.

_EP_ROOT="${GOLEM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# 현재 OS가 Windows(Git Bash/MSYS/Cygwin) 인지
_ep_is_windows() {
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
    *) return 1 ;;
  esac
}

# TMPDIR/TEMP 값에 비ASCII 문자(한글 등)가 섞여 있는지
_ep_has_nonascii_tmp() {
  local tmp_val="${TMPDIR:-${TEMP:-${TMP:-}}}"
  case "$tmp_val" in
    *[!\ -~]*) return 0 ;;
    *) return 1 ;;
  esac
}

# bats 실행 명령 실측 — run.sh 는 벤더링된 bats-core 를 쓰므로 PATH bats 불필요
_ep_bats_cmd() {
  local proj="${GOLEM_PROJECT:-$_EP_ROOT}"
  if [ ! -x "${proj}/tests/bats/bats-core/bin/bats" ] \
     && [ ! -f "${proj}/tests/bats/run.sh" ] \
     && ! command -v bats >/dev/null 2>&1; then
    echo "없음 — 폴백: bats 미설치, tests/bats/ 실행 불가"
    return
  fi
  if _ep_is_windows && _ep_has_nonascii_tmp; then
    echo "TMPDIR=C:/tmp/golem-bats bash tests/bats/run.sh"
  else
    echo "bash tests/bats/run.sh"
  fi
}

# pytest 실행 명령 실측 (web/gateway 존재 시에만)
_ep_pytest_cmd() {
  [ -d "${_EP_ROOT}/web/gateway" ] || { echo ""; return; }

  if command -v uv >/dev/null 2>&1; then
    echo "uv run pytest"
  elif [ -x "${_EP_ROOT}/web/gateway/.venv/Scripts/python.exe" ]; then
    echo ".venv/Scripts/python.exe -m pytest (web/gateway, uv 없음)"
  elif [ -x "${_EP_ROOT}/web/gateway/.venv/bin/python" ]; then
    echo ".venv/bin/python -m pytest (web/gateway, uv 없음)"
  elif command -v python >/dev/null 2>&1; then
    echo "python -m pytest (web/gateway, uv 없음)"
  else
    echo "없음 — 폴백: python 미설치, pytest 실행 불가"
  fi
}

# vitest 실행 명령 실측 (web/client 존재 시에만)
_ep_vitest_cmd() {
  [ -d "${_EP_ROOT}/web/client" ] || { echo ""; return; }

  if command -v npm >/dev/null 2>&1; then
    echo "npm test (web/client)"
  else
    echo "없음 — 폴백: npm 미설치, web/client 테스트 실행 불가"
  fi
}

# 도구 가용성 한 줄 (있으면 경로, 없으면 폴백 메모)
_ep_tool_line() {
  local name="$1"
  local fallback_note="$2"
  if command -v "$name" >/dev/null 2>&1; then
    echo "- ${name}: 있음"
  else
    echo "- ${name}: 없음 — 폴백: ${fallback_note}"
  fi
}

# env_probe_generate — ${GOLEM_DIR}/env.md 생성
# 환경이 바뀌지 않는 한 출력이 byte-stable 하도록 타임스탬프 등은 넣지 않는다
# (prompt-builder 캐시 계약 — 정적 프리픽스 유지).
env_probe_generate() {
  local golem_dir="${GOLEM_DIR:-${_EP_ROOT}/.golem}"
  mkdir -p "$golem_dir" 2>/dev/null
  local out="${golem_dir}/env.md"

  local bats_cmd pytest_cmd vitest_cmd
  bats_cmd="$(_ep_bats_cmd)"
  pytest_cmd="$(_ep_pytest_cmd)"
  vitest_cmd="$(_ep_vitest_cmd)"

  {
    echo "### 검증된 테스트 실행 명령"
    echo "- bats: ${bats_cmd}"
    [ -n "$pytest_cmd" ] && echo "- pytest: ${pytest_cmd}"
    [ -n "$vitest_cmd" ] && echo "- vitest: ${vitest_cmd}"
    echo ""
    echo "### 도구 가용성"
    _ep_tool_line "uv" "미사용, .venv python 직접 호출"
    _ep_tool_line "jq" "미사용 — grep/sed 기반 JSONL 처리"
    _ep_tool_line "npm" "web/client 테스트 실행 불가"
    _ep_tool_line "python" "UUID 생성 등은 /dev/urandom 폴백"
    echo ""
    echo "### OS 함정 노트"
    if _ep_is_windows; then
      echo "- Windows(Git Bash/MSYS) 감지됨"
      echo "  - claude.exe 를 띄우는 서브프로세스는 taskkill //T 로 종료 (timeout/SIGTERM 무효)"
      echo "  - 파일 인플레이스 수정: sed 의 -i 옵션 직접 사용 금지 → _sed_i() 래퍼 사용"
      if _ep_has_nonascii_tmp; then
        echo "  - TMPDIR/TEMP 경로에 비ASCII(한글 등) 포함 — bats symlink 실패 위험, C:/tmp 폴백 필요"
      fi
    else
      echo "- Unix 계열 — sed 의 -i 옵션은 GNU/BSD 차이 있음, _sed_i() 래퍼 사용 권장"
    fi
  } > "$out"
}
