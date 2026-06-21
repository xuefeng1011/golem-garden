#!/usr/bin/env bash
ws="$1"
f="${ws}/log.jsonl"
[ -f "$f" ] || exit 1
# 정확히 1줄 (마지막 개행 유무 허용)
lines=$(grep -c '' "$f")
[ "$lines" -eq 1 ] || exit 1
grep -q '"task":"eval"' "$f" || exit 1
grep -q '"result":"success"' "$f" || exit 1
grep -qE '"files_changed":0[,}]' "$f" || exit 1
# JSON 골격 (시작/끝 중괄호)
head -1 "$f" | grep -qE '^\{.*\}$' || exit 1
exit 0
