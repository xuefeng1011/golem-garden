#!/bin/bash
# mailbox.sh — SOUL 간 파일 기반 통신 시스템
# Usage: source lib/mailbox.sh && mailbox_send nex ryn task_assign "REST API 구현"

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${GOLEM_ROOT}/lib/soul-parser.sh"

# 메일박스 디렉토리
MAILBOX_DIR="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/mailbox"

# ─────────────────────────────────────────────────────────
# 구조화된 시스템 메시지 타입 (Claude Code 패턴)
# 일반 메시지: task_assign, task_done, review_request, info, broadcast
# 시스템 메시지: shutdown_request, shutdown_response, plan_approval,
#              budget_warning, stagnation_alert, escalation
# ─────────────────────────────────────────────────────────

# 팀 종료 요청 (Coordinator → 전체)
mailbox_shutdown_request() {
  local from="$1"
  local reason="${2:-작업 완료}"
  mailbox_broadcast "$from" "SYSTEM:shutdown_request:${reason}"
}

# 팀 종료 응답 (Worker → Coordinator)
mailbox_shutdown_response() {
  local from="$1"
  local coordinator="$2"
  local status="${3:-ready}"  # ready | busy | error
  mailbox_send "$from" "$coordinator" "shutdown_response" "SYSTEM:shutdown_ack:${status}"
}

# 예산 경고 브로드캐스트
mailbox_budget_warning() {
  local level="$1"    # warning | exceeded | stagnating
  local detail="$2"
  mailbox_broadcast "system" "SYSTEM:budget_${level}:${detail}"
}

# 계획 승인 요청 (Coordinator → 사용자)
mailbox_plan_approval() {
  local from="$1"
  local plan_summary="$2"
  [ ! -d "$MAILBOX_DIR" ] && mailbox_init
  local ts=$(date -u +%Y-%m-%dT%H:%M:%S 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
  plan_summary=$(_json_escape "$plan_summary")
  local entry="{\"id\":\"msg_$(date +%s)_$$\",\"from\":\"${from}\",\"to\":\"user\",\"type\":\"plan_approval\",\"content\":\"${plan_summary}\",\"ts\":\"${ts}\",\"status\":\"pending\"}"
  echo "$entry" >> "${MAILBOX_DIR}/broadcast.jsonl"
  echo "[mailbox] ${from} → user: plan_approval (승인 대기)"
}

# 메일박스 초기화
mailbox_init() {
  mkdir -p "$MAILBOX_DIR"
  # 등록된 모든 SOUL에 대해 inbox 생성
  while IFS= read -r soul_file; do
    [ -f "$soul_file" ] || continue
    local name=$(basename "$soul_file" .md)
    [ ! -f "${MAILBOX_DIR}/${name}.jsonl" ] && touch "${MAILBOX_DIR}/${name}.jsonl"
  done < <(_all_soul_files)
  # broadcast 파일
  [ ! -f "${MAILBOX_DIR}/broadcast.jsonl" ] && touch "${MAILBOX_DIR}/broadcast.jsonl"
  echo "[mailbox] 초기화 완료: ${MAILBOX_DIR}"
}

# 메시지 전송
# mailbox_send <from> <to> <type> <content>
# type: task_assign | dependency_ready | task_done | review_request | broadcast | escalation | info
mailbox_send() {
  local from="$1"
  local to="$2"
  local msg_type="$3"
  local content="$4"

  [ ! -d "$MAILBOX_DIR" ] && mailbox_init

  local msg_id="msg_$(date +%s)_$$"
  local ts=$(date -u +%Y-%m-%dT%H:%M:%S 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
  local inbox="${MAILBOX_DIR}/${to}.jsonl"

  content=$(_json_escape "$content")

  local entry="{\"id\":\"${msg_id}\",\"from\":\"${from}\",\"to\":\"${to}\",\"type\":\"${msg_type}\",\"content\":\"${content}\",\"ts\":\"${ts}\",\"status\":\"unread\"}"

  echo "$entry" >> "$inbox"
  echo "[mailbox] ${from} → ${to}: ${msg_type} (${msg_id})"
}

# 브로드캐스트 (전체 SOUL에게 전송)
mailbox_broadcast() {
  local from="$1"
  local content="$2"

  [ ! -d "$MAILBOX_DIR" ] && mailbox_init

  local msg_id="msg_$(date +%s)_$$"
  local ts=$(date -u +%Y-%m-%dT%H:%M:%S 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

  content=$(_json_escape "$content")

  local entry="{\"id\":\"${msg_id}\",\"from\":\"${from}\",\"to\":\"all\",\"type\":\"broadcast\",\"content\":\"${content}\",\"ts\":\"${ts}\",\"status\":\"unread\"}"

  # broadcast 파일에 기록
  echo "$entry" >> "${MAILBOX_DIR}/broadcast.jsonl"

  # 각 SOUL inbox에도 복사
  for inbox in "${MAILBOX_DIR}"/*.jsonl; do
    [ -f "$inbox" ] || continue
    local name=$(basename "$inbox" .jsonl)
    [ "$name" = "broadcast" ] && continue
    [ "$name" = "$from" ] && continue
    echo "$entry" >> "$inbox"
  done

  echo "[mailbox] ${from} → ALL: broadcast (${msg_id})"
}

# 안 읽은 메시지 읽기 + 읽음 처리
mailbox_read() {
  local soul_name="$1"
  local inbox="${MAILBOX_DIR}/${soul_name}.jsonl"

  if [ ! -f "$inbox" ]; then
    echo "[mailbox] ${soul_name}: 수신함 없음"
    return 1
  fi

  local unread_count=$(grep -c '"status":"unread"' "$inbox" 2>/dev/null | tr -d ' \r')
  unread_count=${unread_count:-0}

  if [ "$unread_count" -eq 0 ]; then
    echo "[mailbox] ${soul_name}: 새 메시지 없음"
    return 0
  fi

  echo "=== ${soul_name} 수신함 (미읽음 ${unread_count}건) ==="
  echo ""

  grep '"status":"unread"' "$inbox" | while IFS= read -r line; do
    local from=$(echo "$line" | grep -o '"from":"[^"]*"' | sed 's/"from":"//;s/"//')
    local msg_type=$(echo "$line" | grep -o '"type":"[^"]*"' | sed 's/"type":"//;s/"//')
    local content=$(echo "$line" | grep -o '"content":"[^"]*"' | sed 's/"content":"//;s/"//')
    local ts=$(echo "$line" | grep -o '"ts":"[^"]*"' | sed 's/"ts":"//;s/"//')
    printf "  [%s] %s ← %s: %s\n" "$ts" "$msg_type" "$from" "$content"
  done

  # 읽음 처리
  _sed_i 's/"status":"unread"/"status":"read"/g' "$inbox"
  echo ""
  echo "[mailbox] ${unread_count}건 읽음 처리 완료"
}

# 전체 수신함 조회
mailbox_inbox() {
  local soul_name="$1"
  local inbox="${MAILBOX_DIR}/${soul_name}.jsonl"

  if [ ! -f "$inbox" ]; then
    echo "[mailbox] ${soul_name}: 수신함 없음"
    return 1
  fi

  local total=$(wc -l < "$inbox" | tr -d ' \r')
  total=${total:-0}

  echo "=== ${soul_name} 수신함 (전체 ${total}건) ==="
  echo ""
  printf "%-12s %-14s %-8s %-8s %s\n" "Time" "Type" "From" "Status" "Content"
  printf "%-12s %-14s %-8s %-8s %s\n" "----" "----" "----" "------" "-------"

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local from=$(echo "$line" | grep -o '"from":"[^"]*"' | sed 's/"from":"//;s/"//')
    local msg_type=$(echo "$line" | grep -o '"type":"[^"]*"' | sed 's/"type":"//;s/"//')
    local content=$(echo "$line" | grep -o '"content":"[^"]*"' | sed 's/"content":"//;s/"//')
    local ts=$(echo "$line" | grep -o '"ts":"[^"]*"' | sed 's/"ts":"//;s/"//')
    local status=$(echo "$line" | grep -o '"status":"[^"]*"' | sed 's/"status":"//;s/"//')
    # 시간에서 날짜 부분만 (T 앞)
    local short_ts=$(echo "$ts" | sed 's/T/ /' | cut -c1-16)
    # content 50자 제한
    local short_content=$(echo "$content" | cut -c1-50)
    printf "%-12s %-14s %-8s %-8s %s\n" "$short_ts" "$msg_type" "$from" "$status" "$short_content"
  done < "$inbox"
}

# 미읽음 메시지 수
mailbox_unread_count() {
  local soul_name="$1"
  local inbox="${MAILBOX_DIR}/${soul_name}.jsonl"

  if [ ! -f "$inbox" ]; then
    echo "0"
    return
  fi

  grep -c '"status":"unread"' "$inbox" 2>/dev/null | tr -d ' \r'
}

# 오래된 메시지 정리 (N일 이전)
mailbox_cleanup() {
  local days="${1:-30}"
  local cutoff_ts

  # date 명령 호환성 (GNU vs BSD)
  if date --version 2>/dev/null | grep -q 'GNU'; then
    cutoff_ts=$(date -d "-${days} days" +%Y-%m-%d)
  else
    cutoff_ts=$(date -v-${days}d +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)
  fi

  local total_removed=0

  for inbox in "${MAILBOX_DIR}"/*.jsonl; do
    [ -f "$inbox" ] || continue
    local name=$(basename "$inbox" .jsonl)
    local before=$(wc -l < "$inbox" | tr -d ' \r')

    # cutoff 이후의 메시지만 유지 (ts 필드 기준)
    local tmp="${inbox}.tmp"
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      local msg_date=$(echo "$line" | grep -o '"ts":"[^"]*"' | sed 's/"ts":"//;s/T.*//' | sed 's/"//')
      if [ "$msg_date" \> "$cutoff_ts" ] || [ "$msg_date" = "$cutoff_ts" ]; then
        echo "$line"
      fi
    done < "$inbox" > "$tmp"
    mv "$tmp" "$inbox"

    local after=$(wc -l < "$inbox" | tr -d ' \r')
    local removed=$((before - after))
    total_removed=$((total_removed + removed))
  done

  echo "[mailbox] 정리 완료: ${total_removed}건 삭제 (${days}일 이전)"
}

# 메일박스 대시보드
mailbox_dashboard() {
  echo "=== GolemGarden Mailbox Dashboard ==="
  echo ""
  printf "%-10s %-8s %-8s %s\n" "SOUL" "Unread" "Total" "Latest"
  printf "%-10s %-8s %-8s %s\n" "----" "------" "-----" "------"

  for inbox in "${MAILBOX_DIR}"/*.jsonl; do
    [ -f "$inbox" ] || continue
    local name=$(basename "$inbox" .jsonl)
    [ "$name" = "broadcast" ] && continue

    local total=$(wc -l < "$inbox" | tr -d ' \r')
    total=${total:-0}
    local unread=$(grep -c '"status":"unread"' "$inbox" 2>/dev/null | tr -d ' \r')
    unread=${unread:-0}

    local latest="—"
    if [ "$total" -gt 0 ]; then
      latest=$(tail -1 "$inbox" | grep -o '"type":"[^"]*"' | sed 's/"type":"//;s/"//')
    fi

    printf "%-10s %-8s %-8s %s\n" "$name" "${unread}건" "${total}건" "$latest"
  done
}
