#!/bin/bash
# guard-novice.sh — Novice SOUL의 다중 파일 수정 감지
# PostToolUse hook: Edit 도구 사용 후 수정된 파일 수 체크
# Novice SOUL이 2개 이상 파일을 수정하면 경고

INPUT=$(cat)

# SOUL 랭크 확인 (환경변수로 전달됨)
SOUL_RANK="${GOLEM_SOUL_RANK:-}"

# 랭크 정보가 없으면 패스 (GolemGarden 외부 작업)
if [ -z "$SOUL_RANK" ]; then
  exit 0
fi

# Novice가 아니면 패스
if [ "$SOUL_RANK" != "novice" ]; then
  exit 0
fi

# 현재 세션에서 수정된 파일 수 카운트 (git diff 기반)
MODIFIED_COUNT=$(git diff --name-only 2>/dev/null | wc -l | tr -d ' \r')
MODIFIED_COUNT=${MODIFIED_COUNT:-0}

if [ "$MODIFIED_COUNT" -gt 1 ]; then
  echo "WARNING: Novice SOUL이 ${MODIFIED_COUNT}개 파일을 수정했습니다. 단일 파일 수정 원칙을 확인하세요." >&2
  # 경고만 출력, 차단하지는 않음 (exit 0)
fi

exit 0
