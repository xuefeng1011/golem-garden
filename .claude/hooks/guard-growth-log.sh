#!/usr/bin/env bash
# growth-log JSONL 직접 수정 방지 hook
INPUT=$(cat)
if echo "$INPUT" | grep -q 'growth-log/.*\.jsonl'; then
  echo "BLOCK: growth-log 직접 수정 금지. forge.sh log-add를 사용하세요." >&2
  exit 1
fi
exit 0
