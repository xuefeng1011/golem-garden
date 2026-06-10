#!/bin/bash
# guard-novice.sh — Novice SOUL의 다중 파일 수정 차단 (P0-4)
# PostToolUse hook: Edit 도구 사용 후 수정된 파일 수 체크
# - SOUL 컨텍스트 없음(호스트 세션) → 통과
# - SOUL 컨텍스트는 있는데 랭크 미상 → novice 로 간주 (보수적 기본값)
# - novice + 2개 이상 파일 수정 → 차단 (exit 2 → 에이전트에 시정 피드백)
# env 는 agent_run(lib/agent-runner.sh)이 child claude 세션에 주입한다.

INPUT=$(cat)

SOUL_NAME="${GOLEM_SOUL_NAME:-}"
SOUL_RANK="${GOLEM_SOUL_RANK:-}"

# SOUL 컨텍스트가 전혀 없으면 호스트 세션 (GolemGarden 외부 작업) — 패스
if [ -z "$SOUL_NAME" ] && [ -z "$SOUL_RANK" ]; then
  exit 0
fi

# SOUL 이름은 있는데 랭크 미상 → 보수적으로 novice 간주
if [ -z "$SOUL_RANK" ]; then
  SOUL_RANK="novice"
fi

# Novice가 아니면 패스
if [ "$SOUL_RANK" != "novice" ]; then
  exit 0
fi

# 현재 세션에서 수정된 파일 수 카운트 (git diff 기반)
MODIFIED_COUNT=$(git diff --name-only 2>/dev/null | wc -l | tr -d ' \r')
MODIFIED_COUNT=${MODIFIED_COUNT:-0}

if [ "$MODIFIED_COUNT" -gt 1 ]; then
  echo "BLOCKED: Novice SOUL(${SOUL_NAME:-unknown})이 ${MODIFIED_COUNT}개 파일을 수정했습니다. 단일 파일 수정 원칙 위반 — 방금 변경을 되돌리고 한 파일에 집중하거나, 멀티파일 작업은 상위 랭크 SOUL에 위임하세요." >&2
  exit 2
fi

exit 0
