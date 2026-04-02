#!/bin/bash
# error-recovery.sh — 3단계 실패 복구 시스템
# Usage: source lib/error-recovery.sh && error_recover ryn "REST API 구현" "타입 오류"

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${GOLEM_ROOT}/lib/soul-parser.sh"
source "${GOLEM_ROOT}/lib/growth-log.sh"
source "${GOLEM_ROOT}/lib/prompt-builder.sh"

# 최대 재시도 횟수 (환경변수로 오버라이드 가능)
GOLEM_MAX_RETRY="${GOLEM_MAX_RETRY:-2}"

# 메인 복구 진입점
# error_recover <soul_name> <task> <failure_reason>
error_recover() {
  local soul_name="$1"
  local task="$2"
  local failure_reason="$3"

  echo "=== GolemGarden Error Recovery ==="
  echo "  SOUL: ${soul_name}"
  echo "  태스크: ${task}"
  echo "  실패 원인: ${failure_reason}"
  echo ""

  # Stage 1: 같은 SOUL로 재시도
  echo "[recovery] Stage 1: 재시도 (${soul_name})"
  local retry_result
  retry_result=$(error_retry "$soul_name" "$task" "$failure_reason" 1)
  local retry_status=$?

  if [ $retry_status -eq 0 ]; then
    echo "$retry_result"
    error_log "$soul_name" "$task" "retry" "success"
    return 0
  fi

  # Stage 2: 다른 SOUL에 위임
  echo ""
  echo "[recovery] Stage 2: 위임 시도"
  local delegate_result
  delegate_result=$(error_delegate "$soul_name" "$task" "$failure_reason")
  local delegate_status=$?

  if [ $delegate_status -eq 0 ]; then
    echo "$delegate_result"
    error_log "$soul_name" "$task" "delegate" "success"
    return 0
  fi

  # Stage 3: Director에게 에스컬레이션
  echo ""
  echo "[recovery] Stage 3: 에스컬레이션"
  local escalation_result
  escalation_result=$(error_escalate "$soul_name" "$task" "$failure_reason" "retry=${GOLEM_MAX_RETRY},delegate=failed")
  echo "$escalation_result"
  error_log "$soul_name" "$task" "escalate" "pending"
  return 1
}

# Stage 1: 실패 컨텍스트 주입 후 재시도 프롬프트 생성
# error_retry <soul_name> <task> <failure_reason> <attempt_num>
error_retry() {
  local soul_name="$1"
  local task="$2"
  local failure_reason="$3"
  local attempt="${4:-1}"

  if [ "$attempt" -gt "$GOLEM_MAX_RETRY" ]; then
    echo "[recovery] 최대 재시도 횟수 초과 (${GOLEM_MAX_RETRY}회)"
    return 1
  fi

  local soul_file=$(_resolve_soul_file "$soul_name")
  if [ ! -f "$soul_file" ]; then
    echo "[recovery] ERROR: SOUL 파일 없음: ${soul_name}"
    return 1
  fi

  soul_parse "$soul_file"
  local omc_agent=$(soul_to_omc_agent "$SOUL_ROLE")

  # 실패 컨텍스트가 주입된 재시도 프롬프트 생성
  cat <<RETRY_PROMPT
[GolemGarden Retry — ${SOUL_NAME} (시도 ${attempt}/${GOLEM_MAX_RETRY})]

⚠ 이전 시도 실패 정보:
- 실패 원인: ${failure_reason}
- 시도 횟수: ${attempt}

이전 실패를 참고하여 다른 접근법으로 다시 시도하라:
1. 실패 원인을 먼저 분석
2. 같은 실수를 반복하지 말 것
3. 더 보수적인 접근법 사용

원래 태스크: ${task}

OMC 에이전트: ${omc_agent} (모델: ${SOUL_MODEL})
RETRY_PROMPT

  echo ""
  echo "[recovery] 재시도 프롬프트 생성 완료 (시도 ${attempt}/${GOLEM_MAX_RETRY})"
  echo "[recovery] 실행: OMC ${omc_agent} (model=${SOUL_MODEL})"

  # 실제 실행은 forge-team 스킬이 담당 — 여기서는 프롬프트만 생성
  # 반환값은 호출자가 OMC 에이전트 실행 후 결과에 따라 결정
  return 0
}

# Stage 2: 대체 SOUL 찾기 + 위임 프롬프트 생성
# error_delegate <original_soul> <task> <failure_reason>
error_delegate() {
  local original_soul="$1"
  local task="$2"
  local failure_reason="$3"

  # 태스크 키워드 추출 (공백으로 분리)
  local keywords=$(echo "$task" | tr ' ' '\n' | grep -v '^$' | head -5 | tr '\n' ' ')

  # 대체 SOUL 찾기 (원본 제외)
  local alt_soul=""
  local best_score=0

  while IFS= read -r soul_file; do
    [ -f "$soul_file" ] || continue
    soul_parse "$soul_file"

    # 원본 SOUL 제외
    [ "$SOUL_NAME" = "$original_soul" ] && continue
    # Director 제외
    [ "$SOUL_ROLE" = "director" ] && continue

    local score=$(soul_match_score "$soul_file" "$keywords")
    if [ "$score" -gt "$best_score" ]; then
      best_score=$score
      alt_soul="$SOUL_NAME"
    fi
  done < <(_all_soul_files)

  if [ -z "$alt_soul" ] || [ "$best_score" -eq 0 ]; then
    echo "[recovery] 대체 SOUL 없음 (specialty 매칭 실패)"
    return 1
  fi

  local alt_file=$(_resolve_soul_file "$alt_soul")
  soul_parse "$alt_file"
  local omc_agent=$(soul_to_omc_agent "$SOUL_ROLE")

  echo "[recovery] 대체 SOUL 발견: ${alt_soul} (${SOUL_ROLE}, score=${best_score})"

  cat <<DELEGATE_PROMPT
[GolemGarden Delegate — ${alt_soul} (${original_soul}에서 위임)]

⚠ 위임 정보:
- 원래 담당: ${original_soul}
- 실패 원인: ${failure_reason}
- 위임 사유: ${original_soul}이(가) ${GOLEM_MAX_RETRY}회 실패 후 위임

이 태스크는 다른 SOUL이 실패한 작업입니다.
이전 실패 원인을 참고하되, 독자적 판단으로 접근하라.

태스크: ${task}

OMC 에이전트: ${omc_agent} (모델: ${SOUL_MODEL})
DELEGATE_PROMPT

  echo ""
  echo "DELEGATE:${alt_soul}:${omc_agent}:${SOUL_MODEL}"
  return 0
}

# Stage 3: Director에게 에스컬레이션
# error_escalate <original_soul> <task> <failure_reason> <attempts_log>
error_escalate() {
  local original_soul="$1"
  local task="$2"
  local failure_reason="$3"
  local attempts_log="$4"

  # Director SOUL 찾기
  local director=""
  while IFS= read -r soul_file; do
    [ -f "$soul_file" ] || continue
    soul_parse "$soul_file"
    if [ "$SOUL_ROLE" = "director" ]; then
      director="$SOUL_NAME"
      break
    fi
  done < <(_all_soul_files)

  if [ -z "$director" ]; then
    echo "[recovery] ERROR: Director SOUL 없음 — 에스컬레이션 불가"
    echo "[recovery] 사용자에게 직접 보고합니다:"
    echo ""
    echo "=== 에스컬레이션 보고 ==="
    echo "  태스크: ${task}"
    echo "  담당: ${original_soul}"
    echo "  실패 원인: ${failure_reason}"
    echo "  시도 이력: ${attempts_log}"
    echo "  권장: 수동 개입 필요"
    return 1
  fi

  # mailbox.sh가 source 가능하면 메일박스로 전송
  if [ -f "${GOLEM_ROOT}/lib/mailbox.sh" ]; then
    source "${GOLEM_ROOT}/lib/mailbox.sh"
    mailbox_send "$original_soul" "$director" "escalation" "태스크 실패 에스컬레이션: ${task} | 원인: ${failure_reason} | 이력: ${attempts_log}"
  fi

  cat <<ESCALATION_PROMPT
[GolemGarden Escalation — ${director} (Director)]

🚨 에스컬레이션 보고:
- 원래 담당: ${original_soul}
- 태스크: ${task}
- 실패 원인: ${failure_reason}
- 복구 시도 이력: ${attempts_log}

다음 중 하나를 결정하라:
1. 태스크를 더 작은 단위로 분해하여 재배정
2. 다른 접근법을 제시하고 특정 SOUL에 재배정
3. 태스크를 보류하고 사용자에게 추가 정보 요청
4. 태스크를 취소하고 대안 제시
ESCALATION_PROMPT

  echo ""
  echo "[recovery] ${director}에게 에스컬레이션 완료"
  return 1
}

# 복구 시도 기록 (growth-log에 추가)
# error_log <soul_name> <task> <stage> <outcome>
error_log() {
  local soul_name="$1"
  local task="$2"
  local stage="$3"     # retry | delegate | escalate
  local outcome="$4"   # success | failed | pending

  local log_file="${GROWTH_DIR:-${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/growth-log}/${soul_name}.jsonl"
  local date=$(date +%Y-%m-%d)

  echo "{\"date\":\"${date}\",\"task\":\"${task}\",\"result\":\"recovery_${outcome}\",\"recovery_stage\":\"${stage}\"}" >> "$log_file"
  echo "[recovery] 기록: ${soul_name} — ${task} → ${stage}:${outcome}"
}

# SOUL별 복구 이력 조회
error_history() {
  local soul_name="$1"
  local log_file="${GROWTH_DIR:-${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/growth-log}/${soul_name}.jsonl"

  if [ ! -f "$log_file" ]; then
    echo "[recovery] ${soul_name}: 기록 없음"
    return
  fi

  local recovery_entries=$(grep '"recovery_stage"' "$log_file" 2>/dev/null)
  if [ -z "$recovery_entries" ]; then
    echo "[recovery] ${soul_name}: 복구 이력 없음"
    return
  fi

  echo "=== ${soul_name} 복구 이력 ==="
  echo ""
  printf "%-12s %-30s %-12s %s\n" "Date" "Task" "Stage" "Outcome"
  printf "%-12s %-30s %-12s %s\n" "----" "----" "-----" "-------"

  echo "$recovery_entries" | while IFS= read -r line; do
    [ -z "$line" ] && continue
    local date=$(echo "$line" | grep -o '"date":"[^"]*"' | sed 's/"date":"//;s/"//')
    local task=$(echo "$line" | grep -o '"task":"[^"]*"' | sed 's/"task":"//;s/"//' | cut -c1-28)
    local stage=$(echo "$line" | grep -o '"recovery_stage":"[^"]*"' | sed 's/"recovery_stage":"//;s/"//')
    local result=$(echo "$line" | grep -o '"result":"[^"]*"' | sed 's/"result":"//;s/"//;s/recovery_//')
    printf "%-12s %-30s %-12s %s\n" "$date" "$task" "$stage" "$result"
  done
}
