#!/usr/bin/env bats
# test_portability.bats — macOS/BSD 포터빌리티 회귀 가드
# 목적: GNU 전용 / BSD 비호환 셸 구문이 재유입되는 것을 차단한다.
#   macOS = BSD userland (BSD sed/date/stat) + 기본 Bash 3.2.
# 스코프: lib/*.sh, forge.sh, install.sh, .claude/hooks/*.sh
#   (벤더링된 tests/bats/bats-core/** 는 제외)
# 주석 라인(content가 # 로 시작)은 검사에서 제외한다.

REPO="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

# 스코프 파일을 grep 하고, 순수 주석 라인(`file:line:   # ...`)은 제거한다.
# 매치 없음 → 빈 출력(성공). 사용처: result=$(_grep_scope 'PATTERN')
_grep_scope() {
  grep -rnE "$1" \
    "$REPO/lib" "$REPO/forge.sh" "$REPO/install.sh" "$REPO/.claude/hooks" \
    --include='*.sh' --exclude-dir=bats-core 2>/dev/null \
    | grep -vE ':[0-9]+:[[:space:]]*#' || true
}

# ─────────────────────────────────────────────────────────
# 1. sed -i : BSD 는 `-i ''` 필요 → 반드시 _sed_i/_fc_sed_i 래퍼 경유
#    raw `sed -i` 호출은 래퍼 정의 파일(soul-parser.sh, flow-contract.sh)에만 허용
# ─────────────────────────────────────────────────────────
@test "portability: raw 'sed -i' 는 _sed_i/_fc_sed_i 래퍼 안에서만" {
  result=$(_grep_scope 'sed -i ' | grep -vE '/(soul-parser|flow-contract)\.sh:' || true)
  if [ -n "$result" ]; then
    echo "BSD 비호환 raw 'sed -i' 발견 (래퍼 _sed_i 사용 필요):"
    echo "$result"
    false
  fi
}

# ─────────────────────────────────────────────────────────
# 2. sed append/insert/change : `<addr>a\text` 한 줄 형식은 BSD 에서 깨짐
#    (BSD 는 a\ 뒤 실제 개행 + 텍스트 요구) → awk insert 사용
# ─────────────────────────────────────────────────────────
@test "portability: sed 'a\\\\'/'i\\\\'/'c\\\\' 한 줄 append-insert 금지 (awk 사용)" {
  result=$(_grep_scope '[0-9}][aic]\\')
  if [ -n "$result" ]; then
    echo "BSD 비호환 sed a\\/i\\/c\\ 한 줄 형식 발견 (awk insert 로 대체):"
    echo "$result"
    false
  fi
}

# ─────────────────────────────────────────────────────────
# 3. date -d / --date (GNU 전용) : 같은 파일에 BSD `date -v` 폴백 필수
# ─────────────────────────────────────────────────────────
@test "portability: 'date -d' 사용 시 같은 파일에 'date -v' 폴백 존재" {
  local offenders=""
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    if grep -qE 'date (-d|--date)' "$f" && ! grep -q 'date -v' "$f"; then
      offenders="${offenders}${f}"$'\n'
    fi
  done < <(ls "$REPO"/lib/*.sh "$REPO"/forge.sh "$REPO"/install.sh "$REPO"/.claude/hooks/*.sh 2>/dev/null)
  if [ -n "$offenders" ]; then
    echo "'date -d' 사용하나 BSD 'date -v' 폴백 없는 파일:"
    echo "$offenders"
    false
  fi
}

# ─────────────────────────────────────────────────────────
# 4. macOS 기본 미설치 GNU 명령 금지
#    readlink -f, realpath, stat -c, grep -P, base64 -w
# ─────────────────────────────────────────────────────────
@test "portability: macOS 미지원 GNU 명령 미사용 (readlink -f/realpath/stat -c/grep -P/base64 -w)" {
  result=$(_grep_scope 'readlink -f|stat -c|grep -P|base64 -w|[^_a-zA-Z]realpath ')
  if [ -n "$result" ]; then
    echo "macOS 기본 환경 미지원 GNU 명령 발견:"
    echo "$result"
    false
  fi
}

# ─────────────────────────────────────────────────────────
# 5. Bash 4+ 전용 기능 금지 (macOS 기본 Bash 3.2)
#    declare -A, mapfile, readarray, ${var,,}, ${var^^}
# ─────────────────────────────────────────────────────────
@test "portability: Bash 4+ 전용 기능 미사용 (declare -A/mapfile/readarray/case-conversion)" {
  result=$(_grep_scope 'declare -A|mapfile|readarray|\$\{[A-Za-z_][A-Za-z0-9_]*,,\}|\$\{[A-Za-z_][A-Za-z0-9_]*\^\^\}')
  if [ -n "$result" ]; then
    echo "Bash 3.2 비호환 기능 발견:"
    echo "$result"
    false
  fi
}

# ─────────────────────────────────────────────────────────
# 6. timeout : GNU coreutils 전용. macOS 는 gtimeout.
#    하드코딩 `timeout <N>` 호출은 timeout/gtimeout 탐지 보유 파일에만 허용
# ─────────────────────────────────────────────────────────
@test "portability: 하드코딩 'timeout N' 호출은 agent-runner/doctor 에만 (gtimeout 폴백 보유)" {
  result=$(_grep_scope 'timeout [0-9]' | grep -vE '/(agent-runner|doctor)\.sh:' || true)
  if [ -n "$result" ]; then
    echo "gtimeout 폴백 없는 하드코딩 'timeout N' 호출 발견:"
    echo "$result"
    false
  fi
}

# ─────────────────────────────────────────────────────────
# 7. sed \| alternation (GNU 전용) 금지 — BSD sed 는 \| 를 리터럴로 취급
#    awk 문자단위 파싱으로 대체 (lib/mission.sh _json_get_string 참조)
# ─────────────────────────────────────────────────────────
@test "portability: sed 정규식 \\| alternation (GNU 전용) 재유입 차단" {
  result=$(_grep_scope 'sed.*[\\][|]' || true)
  if [ -n "$result" ]; then
    echo "GNU 전용 sed \\| alternation 재유입 (awk 문자단위 파싱으로 대체):"
    echo "$result"
    false
  fi
}

# ─────────────────────────────────────────────────────────
# 8. run.sh Windows TMPDIR 선택 — 비ASCII(한글 username) TEMP 는
#    bats symlink 생성을 조용히 전멸시키므로 반드시 C:/tmp 폴백 (P0-1 회귀)
#    run.sh 는 set -euo pipefail + 실행부가 있어 통째 source 금지 → 함수만 추출
# ─────────────────────────────────────────────────────────
@test "portability: run.sh 비ASCII TEMP 거부 — C:/tmp/golem-bats 폴백" {
  RUN_SH="$REPO/tests/bats/run.sh"
  eval "$(sed -n '/^_setup_windows_tmpdir()/,/^}/p' "$RUN_SH")"
  TMPDIR= TEMP='C:\Users\한글테스트\AppData\Local\Temp' TMP= _setup_windows_tmpdir 2>/dev/null
  [ "$TMPDIR" = "C:/tmp/golem-bats" ]
  [ "$BATS_TMPDIR" = "C:/tmp/golem-bats" ]
}

@test "portability: run.sh ASCII TEMP 채택 — golem-bats 하위 디렉토리 사용" {
  RUN_SH="$REPO/tests/bats/run.sh"
  eval "$(sed -n '/^_setup_windows_tmpdir()/,/^}/p' "$RUN_SH")"
  local ascii_temp="C:/tmp/pt-ascii.$$"
  mkdir -p "$ascii_temp"
  TMPDIR= TEMP="$ascii_temp" TMP= _setup_windows_tmpdir 2>/dev/null
  [ "$TMPDIR" = "${ascii_temp}/golem-bats" ]
  rm -rf "$ascii_temp"
}
