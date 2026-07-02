#!/usr/bin/env bash
# error-recovery.sh — 실패 복구 프롬프트 생성기 + 에러 분류/이력
#
# 역할: 에러 분류(error_classify), 재시도/위임/에스컬레이션 **프롬프트 생성**
# (error_retry/error_delegate/error_escalate), 복구 이력(error_log/error_history).
# 실행(agent_run 소환)은 하지 않는다 — 호출자(mission-loop 등)의 책임.
#
# Usage: source lib/error-recovery.sh && error_retry ryn "REST API 구현" "타입 오류" 1

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${GOLEM_ROOT}/lib/soul-parser.sh"
source "${GOLEM_ROOT}/lib/growth-log.sh"
source "${GOLEM_ROOT}/lib/prompt-builder.sh"

# 최대 재시도 횟수 (환경변수로 오버라이드 가능)
GOLEM_MAX_RETRY="${GOLEM_MAX_RETRY:-2}"

# ─────────────────────────────────────────────────────────
# Withholding 패턴: 에러를 모델에 즉시 보고하지 않고
# 에이전트 레벨에서 자동 복구를 우선 시도한다.
# 복구 불가능한 에러만 모델에 보고하여 컨텍스트 오염을 방지.
# ─────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────
# 에러 분류 체계 (13가지 — Hermes Agent 패턴 적용)
#
# 각 분류에 복구 힌트(recovery hint)가 포함되어 있어
# 복구 루프가 재분석 없이 바로 행동할 수 있다.
#
# 힌트 필드:
#   retryable        — 재시도 가능 여부 (yes/no)
#   should_compress  — 컨텍스트 압축 필요 (yes/no)
#   should_rotate    — 크레덴셜 교체 필요 (yes/no)
#   should_fallback  — 대체 SOUL/모델 전환 (yes/no)
#   should_decompose — 태스크 분해 필요 (yes/no)
# ─────────────────────────────────────────────────────────

# 에러 분류 + 복구 힌트 반환
# error_classify <error_type> <error_message>
# 출력: classification|action|retryable|compress|rotate|fallback|decompose
# 주의: 출력 필드는 항상 하드코딩된 값이며, 입력(error_msg)에서 파생되지 않음.
#       따라서 error_msg에 '|' 문자가 포함되어도 필드 위치가 깨지지 않음.
error_classify() {
  local error_type="$1"
  local error_msg="$2"

  case "$error_type" in
    # ── 1. 자동 복구 가능 (withhold → 재시도) ──
    timeout)
      echo "timeout|backoff_retry|yes|no|no|no|no" ;;
    rate_limit)
      echo "rate_limit|backoff_rotate|yes|no|yes|no|no" ;;
    transient|server_error)
      echo "server_error|backoff_retry|yes|no|no|no|no" ;;
    overloaded)
      echo "overloaded|backoff_retry|yes|no|no|yes|no" ;;
    file_not_found)
      echo "file_not_found|search_retry|yes|no|no|no|no" ;;
    lock_conflict)
      echo "lock_conflict|wait_retry|yes|no|no|no|no" ;;
    permission)
      echo "permission|fallback_readonly|yes|no|no|no|no" ;;

    # ── 2. 컨텍스트/페이로드 문제 (압축 후 재시도) ──
    context_overflow)
      echo "context_overflow|compress_retry|yes|yes|no|no|no" ;;
    payload_too_large)
      echo "payload_too_large|compress_retry|yes|yes|no|no|no" ;;

    # ── 3. 모델/인증 문제 (폴백) ──
    model_not_found)
      echo "model_not_found|model_fallback|no|no|no|yes|no" ;;
    auth|auth_permanent)
      echo "auth|abort_or_rotate|no|no|yes|no|no" ;;
    billing)
      echo "billing|rotate_credential|no|no|yes|no|no" ;;

    # ── 4. 코드/로직 문제 (모델 개입 필요) ──
    syntax_error)
      echo "syntax_error|model_fix|no|no|no|no|no" ;;
    logic_error)
      echo "logic_error|model_fix|no|no|no|no|no" ;;
    type_error)
      echo "type_error|model_fix|no|no|no|no|no" ;;
    test_failure)
      echo "test_failure|model_analyze|no|no|no|no|no" ;;
    dependency)
      echo "dependency|model_resolve|no|no|no|no|no" ;;

    # ── 5. 태스크 복잡도 문제 (분해 필요) ──
    too_complex)
      echo "too_complex|decompose|no|no|no|no|yes" ;;
    max_turns_exceeded)
      echo "max_turns_exceeded|decompose|no|yes|no|no|yes" ;;

    # ── 6. 알 수 없는 에러 → 메시지 내용으로 분류 ──
    *)
      _error_classify_by_message "$error_msg"
      ;;
  esac
}

# 메시지 내용 기반 에러 분류 (fallback)
_error_classify_by_message() {
  local msg="$1"

  # 컨텍스트 오버플로우 패턴
  if echo "$msg" | grep -qi "context.*length\|too many tokens\|max.*context\|token limit"; then
    echo "context_overflow|compress_retry|yes|yes|no|no|no"
  # 일시적 에러 패턴
  elif echo "$msg" | grep -qi "timeout\|ECONNRESET\|ETIMEDOUT\|429\|503\|retry\|overloaded"; then
    echo "transient|backoff_retry|yes|no|no|no|no"
  # 인증 에러 패턴
  elif echo "$msg" | grep -qi "401\|403\|unauthorized\|forbidden\|invalid.*key\|expired.*token"; then
    echo "auth|abort_or_rotate|no|no|yes|no|no"
  # 모델 없음 패턴
  elif echo "$msg" | grep -qi "model.*not.*found\|not.*available\|does not exist"; then
    echo "model_not_found|model_fallback|no|no|no|yes|no"
  # 코드 에러 패턴
  elif echo "$msg" | grep -qi "SyntaxError\|TypeError\|ReferenceError\|undefined is not\|cannot read"; then
    echo "syntax_error|model_fix|no|no|no|no|no"
  # 복잡도 패턴
  elif echo "$msg" | grep -qi "too complex\|exceeded.*turn\|max.*turn"; then
    echo "max_turns_exceeded|decompose|no|yes|no|no|yes"
  else
    echo "unknown|backoff_retry|yes|no|no|no|no"
  fi
}

# 에러를 보류(withhold)할지 판단 (기존 호환 — error_classify 기반으로 재구현)
# error_should_withhold <error_type> <error_message>
# 반환: withhold (보류 → 자동 복구) | report (모델에 보고)
error_should_withhold() {
  local error_type="$1"
  local error_msg="$2"

  local classification
  classification=$(error_classify "$error_type" "$error_msg")
  local retryable=$(echo "$classification" | cut -d'|' -f3)

  if [ "$retryable" = "yes" ]; then
    echo "withhold"
  else
    echo "report"
  fi
}

# Withholding 자동 복구 시도 (모델에 보고하기 전)
# error_classify의 복구 힌트를 활용하여 행동 결정
# error_withhold_recover <soul_name> <error_type> <error_message> <attempt>
# 반환: 0=복구 성공, 1=복구 실패(모델에 보고 필요)
error_withhold_recover() {
  local soul_name="$1"
  local error_type="$2"
  local error_msg="$3"
  local attempt="${4:-1}"

  local classification
  classification=$(error_classify "$error_type" "$error_msg")
  local action=$(echo "$classification" | cut -d'|' -f2)
  local retryable=$(echo "$classification" | cut -d'|' -f3)
  local should_compress=$(echo "$classification" | cut -d'|' -f4)
  local should_fallback=$(echo "$classification" | cut -d'|' -f6)
  local should_decompose=$(echo "$classification" | cut -d'|' -f7)

  echo "[recovery:withhold] ${soul_name}: ${error_type} → ${action} (attempt ${attempt}/${GOLEM_MAX_RETRY})"

  # 재시도 불가 → 즉시 보고
  if [ "$retryable" != "yes" ]; then
    echo "[recovery:withhold] 자동 복구 불가 (${action}) — 모델에 보고"
    return 1
  fi

  case "$action" in
    backoff_retry)
      local wait_sec=$((attempt * 3))
      echo "[recovery:withhold] ${wait_sec}초 대기 후 재시도"
      echo "WITHHOLD_RETRY:${wait_sec}"
      return 0
      ;;
    backoff_rotate)
      local wait_sec=$((attempt * 5))
      echo "[recovery:withhold] ${wait_sec}초 대기 + 크레덴셜 로테이션 권고"
      echo "WITHHOLD_RETRY:${wait_sec}"
      return 0
      ;;
    compress_retry)
      echo "[recovery:withhold] 컨텍스트 압축 후 재시도 권고"
      echo "WITHHOLD_COMPRESS"
      return 0
      ;;
    search_retry)
      echo "[recovery:withhold] 파일 검색으로 대체 경로 탐색"
      echo "WITHHOLD_SEARCH"
      return 0
      ;;
    wait_retry)
      echo "[recovery:withhold] 2초 대기 후 재시도"
      echo "WITHHOLD_RETRY:2"
      return 0
      ;;
    fallback_readonly)
      echo "[recovery:withhold] 읽기 전용 모드로 폴백"
      echo "WITHHOLD_FALLBACK:readonly"
      return 0
      ;;
    *)
      echo "[recovery:withhold] 알 수 없는 액션: ${action} — 백오프 재시도"
      echo "WITHHOLD_RETRY:$((attempt * 3))"
      return 0
      ;;
  esac
}

# [REMOVED] error_recover — 구 OMC 시대의 3단계 오케스트레이터.
# error_retry가 프롬프트만 생성하고 무조건 성공을 반환해 Stage 1이 항상
# "즉시 성공"으로 위장되는 no-op이었다 (실제 재시도·위임 없음).
# 결정론적 복구 루프는 mission-loop(P1-6)가 error_retry 프롬프트를 소비해 수행한다.

# Stage 1: 실패 컨텍스트 주입 후 재시도 프롬프트 생성
# error_retry <soul_name> <task> <failure_reason> <attempt_num>
# 출력: 재시도 프롬프트 (stdout). 실행(agent_run)은 호출자 책임.
# 반환: 0=프롬프트 생성됨, 1=재시도 상한 초과 또는 SOUL 없음
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

  # 실패 컨텍스트가 주입된 재시도 프롬프트 생성 — stdout은 프롬프트만
  # (호출자가 그대로 agent_run에 넘길 수 있도록 상태 메시지는 stderr).
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
RETRY_PROMPT

  echo "[recovery] 재시도 프롬프트 생성 완료 — ${SOUL_NAME} (role=${SOUL_ROLE}, model=${SOUL_MODEL}, 시도 ${attempt}/${GOLEM_MAX_RETRY})" >&2
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

  echo "[recovery] 대체 SOUL 발견: ${alt_soul} (${SOUL_ROLE}, score=${best_score})" >&2

  cat <<DELEGATE_PROMPT
[GolemGarden Delegate — ${alt_soul} (${original_soul}에서 위임)]

⚠ 위임 정보:
- 원래 담당: ${original_soul}
- 실패 원인: ${failure_reason}
- 위임 사유: ${original_soul}이(가) ${GOLEM_MAX_RETRY}회 실패 후 위임

이 태스크는 다른 SOUL이 실패한 작업입니다.
이전 실패 원인을 참고하되, 독자적 판단으로 접근하라.

태스크: ${task}
DELEGATE_PROMPT

  echo "DELEGATE:${alt_soul}:${SOUL_ROLE}:${SOUL_MODEL}" >&2
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

  task=$(_json_escape "$task")
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
