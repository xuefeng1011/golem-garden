#!/bin/bash
# knowledge-sync.sh — 지식 승격 시스템
# Usage: source lib/knowledge-sync.sh

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GOLEM_DIR="${GOLEM_DIR:-${GOLEM_ROOT}}"
SYNC_DIR="${GOLEM_DIR}/sync"
PENDING_FILE="${SYNC_DIR}/pending.jsonl"
HISTORY_FILE="${SYNC_DIR}/history.jsonl"

# sync 디렉토리 초기화
_init_sync() {
  mkdir -p "$SYNC_DIR"
  [ ! -f "$PENDING_FILE" ] && touch "$PENDING_FILE"
  [ ! -f "$HISTORY_FILE" ] && touch "$HISTORY_FILE"
}

# 학습 기록 추가 (작업 완료 시 호출)
knowledge_record() {
  local soul_name="$1"
  local learning="$2"
  local scope="${3:-unknown}"        # universal | project | unknown
  local confidence="${4:-medium}"    # high | medium | low
  local source_task="${5:-}"

  _init_sync

  local date=$(date +%Y-%m-%d)
  local entry="{\"date\":\"${date}\",\"soul\":\"${soul_name}\",\"learning\":\"${learning}\",\"scope\":\"${scope}\",\"confidence\":\"${confidence}\",\"source_task\":\"${source_task}\",\"status\":\"pending\"}"

  echo "$entry" >> "$PENDING_FILE"
  echo "[knowledge] 학습 기록: ${soul_name} — ${learning} (${scope}/${confidence})"
}

# 승격 대기열 조회
knowledge_pending() {
  _init_sync

  local count=$(wc -l < "$PENDING_FILE" | tr -d ' \r')
  echo "=== 승격 대기열 (${count}건) ==="
  echo ""

  if [ "$count" -eq 0 ] || [ ! -s "$PENDING_FILE" ]; then
    echo "(대기 중인 학습 없음)"
    return
  fi

  printf "%-6s %-10s %-12s %-10s %s\n" "No" "SOUL" "Scope" "Conf" "Learning"
  printf "%-6s %-10s %-12s %-10s %s\n" "---" "----" "-----" "----" "--------"

  local i=1
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local soul=$(echo "$line" | grep -o '"soul":"[^"]*"' | sed 's/"soul":"//;s/"//')
    local learning=$(echo "$line" | grep -o '"learning":"[^"]*"' | sed 's/"learning":"//;s/"//')
    local scope=$(echo "$line" | grep -o '"scope":"[^"]*"' | sed 's/"scope":"//;s/"//')
    local conf=$(echo "$line" | grep -o '"confidence":"[^"]*"' | sed 's/"confidence":"//;s/"//')
    printf "%-6s %-10s %-12s %-10s %s\n" "$i" "$soul" "$scope" "$conf" "$learning"
    i=$((i + 1))
  done < "$PENDING_FILE"
}

# 자동 승격 대상 필터 (universal + high + review pass)
knowledge_auto_candidates() {
  _init_sync
  grep '"scope":"universal"' "$PENDING_FILE" 2>/dev/null | grep '"confidence":"high"' || true
}

# 심사 결과 기록
knowledge_judge() {
  local line_num="$1"
  local verdict="$2"        # promote | hold | reject
  local reason="${3:-}"

  _init_sync

  local line=$(sed -n "${line_num}p" "$PENDING_FILE")
  if [ -z "$line" ]; then
    echo "[knowledge] ERROR: ${line_num}번 항목 없음"
    return 1
  fi

  local date=$(date +%Y-%m-%d)
  local soul=$(echo "$line" | grep -o '"soul":"[^"]*"' | sed 's/"soul":"//;s/"//')
  local learning=$(echo "$line" | grep -o '"learning":"[^"]*"' | sed 's/"learning":"//;s/"//')

  # 히스토리에 기록
  echo "{\"date\":\"${date}\",\"soul\":\"${soul}\",\"learning\":\"${learning}\",\"verdict\":\"${verdict}\",\"reason\":\"${reason}\"}" >> "$HISTORY_FILE"

  # pending에서 제거
  sed -i "${line_num}d" "$PENDING_FILE"

  case "$verdict" in
    promote)
      echo "[knowledge] ✅ 승격: ${learning}"
      ;;
    hold)
      echo "[knowledge] ⚠️ 보류: ${learning} (${reason})"
      ;;
    reject)
      echo "[knowledge] ❌ 기각: ${learning} (${reason})"
      ;;
  esac
}

# 승격 실행 (글로벌 SOUL에 전문 지식 추가)
knowledge_promote() {
  local soul_name="$1"
  local learning="$2"

  local soul_file="${GOLEM_ROOT}/souls/${soul_name}.md"
  if [ ! -f "$soul_file" ]; then
    echo "[knowledge] ERROR: 글로벌 SOUL 없음: ${soul_name}"
    return 1
  fi

  # "## 전문 지식" 섹션 끝에 추가
  # 이미 같은 내용이 있으면 건너뜀
  if grep -qF "$learning" "$soul_file" 2>/dev/null; then
    echo "[knowledge] SKIP: 이미 존재하는 지식 — ${learning}"
    return 0
  fi

  # 전문 지식 섹션의 마지막 항목 뒤에 추가
  sed -i "/^## 전문 지식/,/^## /{/^## [^전]/!{/^$/!{/^- /H}}}" "$soul_file"
  # 간단하게: 전문 지식 섹션의 마지막 - 항목 뒤에 삽입
  local last_line=$(grep -n "^- " "$soul_file" | tail -1 | cut -d: -f1)
  if [ -n "$last_line" ]; then
    sed -i "${last_line}a\\- ${learning} (자동 승격: $(date +%Y-%m-%d))" "$soul_file"
  fi

  echo "[knowledge] ✅ 글로벌 반영: ${soul_name} ← ${learning}"
}

# 심사 히스토리 조회
knowledge_history() {
  _init_sync

  echo "=== 심사 히스토리 ==="
  echo ""

  if [ ! -s "$HISTORY_FILE" ]; then
    echo "(히스토리 없음)"
    return
  fi

  printf "%-12s %-10s %-10s %s\n" "Date" "SOUL" "Verdict" "Learning"
  printf "%-12s %-10s %-10s %s\n" "----" "----" "-------" "--------"

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local date=$(echo "$line" | grep -o '"date":"[^"]*"' | sed 's/"date":"//;s/"//')
    local soul=$(echo "$line" | grep -o '"soul":"[^"]*"' | sed 's/"soul":"//;s/"//')
    local verdict=$(echo "$line" | grep -o '"verdict":"[^"]*"' | sed 's/"verdict":"//;s/"//')
    local learning=$(echo "$line" | grep -o '"learning":"[^"]*"' | sed 's/"learning":"//;s/"//')
    printf "%-12s %-10s %-10s %s\n" "$date" "$soul" "$verdict" "$learning"
  done < "$HISTORY_FILE"
}

# 전체 현황 대시보드
knowledge_dashboard() {
  _init_sync

  local pending=$(wc -l < "$PENDING_FILE" 2>/dev/null | tr -d ' \r')
  [ -z "$pending" ] && pending=0
  local promoted=$(grep -c '"verdict":"promote"' "$HISTORY_FILE" 2>/dev/null | tr -d '\r' || echo "0")
  local rejected=$(grep -c '"verdict":"reject"' "$HISTORY_FILE" 2>/dev/null | tr -d '\r' || echo "0")
  local held=$(grep -c '"verdict":"hold"' "$HISTORY_FILE" 2>/dev/null | tr -d '\r' || echo "0")

  echo "=== Knowledge Sync Dashboard ==="
  echo ""
  echo "  대기: ${pending}건"
  echo "  승격: ${promoted}건"
  echo "  보류: ${held}건"
  echo "  기각: ${rejected}건"
  echo ""

  if [ "$pending" -gt 0 ]; then
    echo "--- 대기 중 ---"
    knowledge_pending
  fi
}
