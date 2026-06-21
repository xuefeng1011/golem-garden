#!/usr/bin/env bash
# verify.sh <workspace>
# exit 0 = pass, exit 1 = fail
ws="$1"
[ -f "${ws}/process.sh" ] || exit 1

# (a) 출력 동등성 검증
out=$(bash "${ws}/process.sh" 2>/dev/null)
expected=$(printf '[alpha|00042|ok]\n[beta|00000|ok]\n[gamma|01000|err]')
[ "$out" = "$expected" ] || exit 1

# (b) 중복 제거 검증: 핵심 포맷 지시자 '%05d' 가 1줄 이하여야 한다
#     원본 3개 블록 → 각 줄에 1회씩 총 3줄; 함수 추출 후 1줄만 남아야 함
count=$(grep -c '%05d' "${ws}/process.sh" 2>/dev/null)
count="${count:-99}"
[ "$count" -le 1 ] || exit 1

# (c) 조건 로직 중복 검증: '-ge 0' 판정이 1줄 이하여야 한다
#     원본 3개 블록 → 각 줄에 1회씩 총 3줄; 함수 추출 후 1줄만 남아야 함
count_cond=$(grep -c '\-ge 0' "${ws}/process.sh" 2>/dev/null)
count_cond="${count_cond:-99}"
[ "$count_cond" -le 1 ] || exit 1

exit 0
