#!/usr/bin/env bash
# guard-mailbox.sh — mailbox JSONL 직접 수정 방지
# PreToolUse hook: Edit/Write로 mailbox/*.jsonl 직접 수정 차단
INPUT=$(cat)
if echo "$INPUT" | grep -q 'mailbox/.*\.jsonl'; then
  echo "BLOCK: mailbox 직접 수정 금지. forge mailbox 명령을 사용하세요." >&2
  exit 1
fi
exit 0
