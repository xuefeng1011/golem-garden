#!/usr/bin/env bash
# run.sh — GolemGarden bats 테스트 실행 래퍼
# 사용법: bash tests/bats/run.sh [bats 옵션...]
# 예시:  bash tests/bats/run.sh --version
#        bash tests/bats/run.sh --tap
#        bash tests/bats/run.sh tests/bats/test_soul_parser.bats

set -euo pipefail

# Windows Git Bash에서 bats-core symlink 실패 워크어라운드.
# bats는 BATS_TMPDIR > TMPDIR 순으로 사용하므로 둘 다 export.
# 사용자가 이미 TMPDIR을 설정한 경우 override 금지.
_setup_windows_tmpdir() {
  # 사용자가 명시적으로 Windows native path를 설정한 경우 그대로 사용.
  # Unix-style(/tmp)은 bats symlink 문제를 일으키므로 override 대상으로 간주.
  local existing="${TMPDIR:-}"
  if [[ -n "$existing" && "$existing" != /tmp* ]]; then
    export BATS_TMPDIR="$existing"
    return
  fi

  # TEMP/TMP가 Windows native path(드라이브 문자 또는 backslash 포함)인 경우만 사용.
  # Git Bash에서 /tmp로 변환된 값은 무시한다.
  local win_tmp=""
  for candidate in "${TEMP:-}" "${TMP:-}"; do
    # Windows path: C:\ 또는 C:/ 형태로 시작
    if [[ "$candidate" =~ ^[A-Za-z]: ]]; then
      win_tmp="$candidate"
      break
    fi
  done

  local bats_tmp
  if [[ -n "$win_tmp" ]]; then
    # backslash → forward slash (bash 친화)
    bats_tmp="${win_tmp//\\//}/golem-bats"
  else
    # ASCII-safe fallback: 한글 등 비ASCII 경로는 환경변수 처리 시 깨질 수 있으므로 사용 금지
    bats_tmp="C:/tmp/golem-bats"
  fi

  # 생성 실패 시 ASCII-safe C:/tmp 재시도
  if ! mkdir -p "$bats_tmp" 2>/dev/null; then
    bats_tmp="C:/tmp/golem-bats"
    mkdir -p "$bats_tmp"
  fi

  export TMPDIR="$bats_tmp"
  export BATS_TMPDIR="$bats_tmp"

  if [[ "${BATS_VERBOSE:-0}" == "1" ]]; then
    echo "[bats] Windows TMPDIR -> $bats_tmp" >&2
  fi
}

# OSTYPE(msys/cygwin) 또는 uname -s(MINGW*/MSYS*/CYGWIN*)로 Windows 감지
case "${OSTYPE:-}" in
  msys*|cygwin*|win32*)
    _setup_windows_tmpdir ;;
  *)
    case "$(uname -s 2>/dev/null)" in
      MINGW*|MSYS*|CYGWIN*)
        _setup_windows_tmpdir ;;
    esac ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATS_BIN="${SCRIPT_DIR}/bats-core/bin/bats"

if [[ ! -x "$BATS_BIN" ]]; then
  echo "[ERROR] bats-core not found at: $BATS_BIN" >&2
  echo "  벤더링된 bats-core가 없습니다. README.md의 설치 안내를 확인하세요." >&2
  exit 1
fi

# 인수가 없으면 tests/bats/*.bats 전체 실행
if [[ $# -eq 0 ]]; then
  exec "$BATS_BIN" "${SCRIPT_DIR}"/*.bats
else
  exec "$BATS_BIN" "$@"
fi
