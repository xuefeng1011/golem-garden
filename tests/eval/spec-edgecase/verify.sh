#!/usr/bin/env bash
# verify.sh <workspace>
# exit 0 = pass, exit 1 = fail
# 채점: spec.txt 에 묻힌 엣지케이스 5개 검증

ws="$1"
fail=0

check() {
  local input="$1" expected="$2"
  local actual
  actual=$(bash "${ws}/normalize.sh" "$input" 2>/dev/null)
  if [ "$actual" != "$expected" ]; then
    echo "FAIL: input=$(printf '%q' "$input") expected='$expected' got='$actual'" >&2
    fail=1
  fi
}

# 구현 파일 존재 여부
[ -f "${ws}/normalize.sh" ] || { echo "FAIL: normalize.sh not found" >&2; exit 1; }

# 엣지케이스 1 (§3-2): 공백만 있는 인자 → "EMPTY"
check "   " "EMPTY"

# 엣지케이스 2 (§3-1 + §4-1): 양끝 공백 제거 후 하이픈 시작 → "ERR:invalid"
check "  -test  " "ERR:invalid"

# 엣지케이스 3 (§4-2): 선행 0 제거 후 NUM: 접두어
check "007" "NUM:7"

# 엣지케이스 4 (§5): 12자 초과 → 앞 12자만; "EMPTY"는 제한 없음
#   입력 "ABCDEFGHIJKLMNOP" → 소문자 "abcdefghijklmnop"(16자) → 앞 12자
check "ABCDEFGHIJKLMNOP" "abcdefghijkl"

# 엣지케이스 5 (§5): NUM: 출력에도 12자 제한 적용
#   "9999999999999"(13자리) → "NUM:9999999999999"(17자) → 앞 12자 "NUM:99999999"
check "9999999999999" "NUM:99999999"

[ "$fail" -eq 0 ] && exit 0 || exit 1
