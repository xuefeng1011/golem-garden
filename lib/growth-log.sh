#!/bin/bash
# growth-log.sh — SOUL 성장 기록 관리
# Usage: source lib/growth-log.sh && growth_log_append ryn "REST API 구현" success 5 12

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# 프로젝트별 .golem/growth-log/ 사용, 없으면 글로벌 폴백
GROWTH_DIR="${GOLEM_DIR:-${GOLEM_ROOT}}/growth-log"

# growth-log 디렉토리 없으면 자동 생성
[ ! -d "$GROWTH_DIR" ] && mkdir -p "$GROWTH_DIR"

# 성장 기록 추가
growth_log_append() {
  local soul_name="$1"
  local task="$2"
  local result="$3"           # success | fail
  local files_changed="${4:-0}"
  local tests_passed="${5:-0}"
  local reviewer="${6:-}"
  local review_result="${7:-}"

  local log_file="${GROWTH_DIR}/${soul_name}.jsonl"
  local date=$(date +%Y-%m-%d)

  local entry="{\"date\":\"${date}\",\"task\":\"${task}\",\"result\":\"${result}\",\"files_changed\":${files_changed},\"tests_passed\":${tests_passed}"

  if [ -n "$reviewer" ]; then
    entry="${entry},\"reviewer\":\"${reviewer}\",\"review_result\":\"${review_result}\"}"
  else
    entry="${entry}}"
  fi

  echo "$entry" >> "$log_file"
  echo "[growth-log] ${soul_name}: ${task} → ${result}"
}

# 랭크 승급 이벤트 기록
growth_log_rank_up() {
  local soul_name="$1"
  local from_rank="$2"
  local to_rank="$3"
  local trigger="$4"

  local log_file="${GROWTH_DIR}/${soul_name}.jsonl"
  local date=$(date +%Y-%m-%d)

  echo "{\"date\":\"${date}\",\"task\":\"RANK_UP\",\"result\":\"${from_rank}→${to_rank}\",\"trigger\":\"${trigger}\"}" >> "$log_file"
  echo "[growth-log] ${soul_name}: RANK UP! ${from_rank} → ${to_rank} (${trigger})"
}

# 태스크 완료 횟수 카운트 (forge-init, RANK_UP 제외)
growth_log_task_count() {
  local soul_name="$1"
  local log_file="${GROWTH_DIR}/${soul_name}.jsonl"

  if [ ! -f "$log_file" ]; then
    echo "0"
    return
  fi

  grep '"result":"success"' "$log_file" 2>/dev/null | grep -v '"task":"forge-init"' | grep -v '"task":"RANK_UP"' | wc -l | tr -d ' \r'
}

# 연속 무결함 카운트 (최근 연속으로 issues_found=0 또는 review_result=pass)
growth_log_streak() {
  local soul_name="$1"
  local log_file="${GROWTH_DIR}/${soul_name}.jsonl"
  local streak=0

  if [ ! -f "$log_file" ]; then
    echo "0"
    return
  fi

  # 최근 항목부터 역순으로 연속 성공 카운트
  # tac 대신 tail -r 폴백, 파이프 서브셸 대신 프로세스 치환 사용
  local reversed
  if command -v tac >/dev/null 2>&1; then
    reversed=$(tac "$log_file")
  else
    reversed=$(tail -r "$log_file" 2>/dev/null || sed -n '1!G;h;$p' "$log_file")
  fi

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    # RANK_UP 이벤트는 건너뜀
    echo "$line" | grep -q '"task":"RANK_UP"' && continue
    # forge-init 이벤트는 건너뜀
    echo "$line" | grep -q '"task":"forge-init"' && continue
    # pack-install 이벤트는 건너뜀
    echo "$line" | grep -q '"task":"pack-install' && continue

    if echo "$line" | grep -q '"result":"success"'; then
      streak=$((streak + 1))
    else
      break
    fi
  done <<< "$reversed"
  echo "$streak"
}

# 성공률 계산 (%)
growth_log_success_rate() {
  local soul_name="$1"
  local log_file="${GROWTH_DIR}/${soul_name}.jsonl"

  if [ ! -f "$log_file" ]; then
    echo "0"
    return
  fi

  local total=$(grep '"task":' "$log_file" 2>/dev/null | grep -v '"task":"RANK_UP"' | grep -v '"task":"forge-init"' | wc -l | tr -d ' \r')
  total=${total:-0}

  if [ "$total" -eq 0 ]; then
    echo "100"
    return
  fi

  local success=$(grep '"result":"success"' "$log_file" 2>/dev/null | grep -v '"task":"RANK_UP"' | grep -v '"task":"forge-init"' | wc -l | tr -d ' \r')
  success=${success:-0}
  echo $(( (success * 100) / total ))
}

# SOUL 성장 요약 출력
growth_log_summary() {
  local soul_name="$1"
  local task_count=$(growth_log_task_count "$soul_name")
  local success_rate=$(growth_log_success_rate "$soul_name")
  local streak=$(growth_log_streak "$soul_name")

  echo "=== ${soul_name} 성장 요약 ==="
  echo "  태스크 완료: ${task_count}건"
  echo "  성공률: ${success_rate}%"
  echo "  연속 무결함: ${streak}건"
}

# 전체 SOUL 성장 대시보드
growth_log_dashboard() {
  echo "=== GolemGarden Growth Dashboard ==="
  echo ""
  printf "%-10s %-8s %-10s %-8s %s\n" "SOUL" "Tasks" "Rate" "Streak" "Last Task"
  printf "%-10s %-8s %-10s %-8s %s\n" "----" "-----" "----" "------" "---------"

  for log_file in "${GROWTH_DIR}"/*.jsonl; do
    [ -f "$log_file" ] || continue
    local name=$(basename "$log_file" .jsonl)
    local tasks=$(growth_log_task_count "$name")
    local rate=$(growth_log_success_rate "$name")
    local streak=$(growth_log_streak "$name")
    local last_task=$(tail -1 "$log_file" | grep -o '"task":"[^"]*"' | head -1 | sed 's/"task":"//;s/"//')

    printf "%-10s %-8s %-10s %-8s %s\n" "$name" "${tasks}건" "${rate}%" "${streak}연속" "$last_task"
  done
}
