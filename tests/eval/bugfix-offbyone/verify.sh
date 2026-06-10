#!/bin/bash
ws="$1"
[ -f "${ws}/count.sh" ] || exit 1
out=$(bash "${ws}/count.sh" 5 2>/dev/null | tr -d '\r')
expected=$(printf '1\n2\n3\n4\n5')
[ "$out" = "$expected" ] || exit 1
# 경계: n=1
out1=$(bash "${ws}/count.sh" 1 2>/dev/null | tr -d '\r')
[ "$out1" = "1" ] || exit 1
exit 0
