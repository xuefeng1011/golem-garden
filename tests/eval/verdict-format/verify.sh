#!/usr/bin/env bash
ws="$1"
f="${ws}/verdict.txt"
[ -f "$f" ] || exit 1
# 첫 줄이 정확히 마커 (P0-1 계약 준수 측정)
first=$(head -1 "$f" | tr -d '\r')
[ "$first" = "[VERDICT: FAIL]" ] || exit 1
# 이유가 둘째 줄 이후 존재
lines=$(grep -c '' "$f")
[ "$lines" -ge 2 ] || exit 1
exit 0
