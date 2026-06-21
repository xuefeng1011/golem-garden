#!/usr/bin/env bash
# growth-log.sh — SOUL 성장 기록 관리
# Usage: source lib/growth-log.sh && growth_log_append ryn "REST API 구현" success 5 12

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${GOLEM_ROOT}/lib/soul-parser.sh"
# 프로젝트별 .golem/growth-log/ 사용, 없으면 글로벌 폴백
GROWTH_DIR="${GOLEM_DIR:-${GOLEM_ROOT}}/growth-log"

# growth-log 디렉토리 없으면 자동 생성
[ ! -d "$GROWTH_DIR" ] && mkdir -p "$GROWTH_DIR"

# 성장 기록 추가 (비용 추적 필드 포함)
growth_log_append() {
  local soul_name="$1"
  local task="$2"
  local result="$3"           # success | fail
  local files_changed="${4:-0}"
  local tests_passed="${5:-0}"
  local reviewer="${6:-}"
  local review_result="${7:-}"
  # Phase 1 확장: 비용 추적 필드
  local tokens_in="${8:-0}"
  local tokens_out="${9:-0}"
  local tokens_cache="${10:-0}"
  local cost_usd="${11:-0.000}"
  local model="${12:-}"
  local duration_ms="${13:-0}"

  local log_file="${GROWTH_DIR}/${soul_name}.jsonl"
  local date=$(date +%Y-%m-%d)

  local task_display="$task"
  task=$(_json_escape "$task")
  reviewer=$(_json_escape "$reviewer")
  review_result=$(_json_escape "$review_result")
  model=$(_json_escape "$model")

  local entry="{\"date\":\"${date}\",\"task\":\"${task}\",\"result\":\"${result}\",\"files_changed\":${files_changed},\"tests_passed\":${tests_passed}"

  if [ -n "$reviewer" ]; then
    entry="${entry},\"reviewer\":\"${reviewer}\",\"review_result\":\"${review_result}\""
  fi

  if [ "$tokens_in" -gt 0 ] 2>/dev/null; then
    entry="${entry},\"tokens_in\":${tokens_in},\"tokens_out\":${tokens_out},\"tokens_cache\":${tokens_cache},\"cost_usd\":${cost_usd},\"model\":\"${model}\",\"duration_ms\":${duration_ms}"
  fi

  entry="${entry}}"

  echo "$entry" >> "$log_file"
  _growth_log_update_summary "$soul_name"

  # forge-board `updated:` 타임스탬프 자동 갱신 (문서 정합화 2026-06-11).
  # 태스크 행 추가(board_add_task)는 review/rank 이벤트만 수행 — 매 run 기록 시
  # 보드가 범람하므로 여기서는 타임스탬프만 touch 한다.
  if ! type board_update_timestamp >/dev/null 2>&1 && [ -f "${GOLEM_ROOT}/lib/forge-board.sh" ]; then
    # shellcheck source=/dev/null
    source "${GOLEM_ROOT}/lib/forge-board.sh" 2>/dev/null
  fi
  if type board_update_timestamp >/dev/null 2>&1 && type _sed_i >/dev/null 2>&1; then
    board_update_timestamp 2>/dev/null
  fi

  echo "[growth-log] ${soul_name}: ${task_display} → ${result}"
}

# 랭크 승급 이벤트 기록
growth_log_rank_up() {
  local soul_name="$1"
  local from_rank="$2"
  local to_rank="$3"
  local trigger="$4"

  local log_file="${GROWTH_DIR}/${soul_name}.jsonl"
  local date=$(date +%Y-%m-%d)
  trigger=$(_json_escape "$trigger")

  echo "{\"date\":\"${date}\",\"task\":\"RANK_UP\",\"result\":\"${from_rank}→${to_rank}\",\"trigger\":\"${trigger}\"}" >> "$log_file"
  _growth_log_update_summary "$soul_name"
  echo "[growth-log] ${soul_name}: RANK UP! ${from_rank} → ${to_rank} (${trigger})"
}

_growth_log_update_summary() {
  local soul_name="$1"
  local log_file="${GROWTH_DIR}/${soul_name}.jsonl"
  local summary_file="${GROWTH_DIR}/${soul_name}.summary"

  [ ! -f "$log_file" ] && return

  local task_count=$(grep '"result":"success"' "$log_file" 2>/dev/null | grep -v '"task":"forge-init"' | grep -v '"task":"RANK_UP"' | grep -v '"task":"pack-install' | grep -v '"task":"forge-soul-create"' | wc -l | tr -d ' \r')
  task_count=${task_count:-0}

  local total=$(grep '"task":' "$log_file" 2>/dev/null | grep -v '"task":"RANK_UP"' | grep -v '"task":"forge-init"' | grep -v '"task":"pack-install' | grep -v '"task":"forge-soul-create"' | wc -l | tr -d ' \r')
  total=${total:-0}
  local success_rate=100
  if [ "$total" -gt 0 ]; then
    success_rate=$(( (task_count * 100) / total ))
  fi

  local streak=0
  local reversed
  if command -v tac >/dev/null 2>&1; then
    reversed=$(tac "$log_file")
  else
    reversed=$(tail -r "$log_file" 2>/dev/null || sed -n '1!G;h;$p' "$log_file")
  fi
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    echo "$line" | grep -q '"task":"RANK_UP"' && continue
    echo "$line" | grep -q '"task":"forge-init"' && continue
    echo "$line" | grep -q '"task":"pack-install' && continue
    if echo "$line" | grep -q '"result":"success"'; then
      streak=$((streak + 1))
    else
      break
    fi
  done <<< "$reversed"

  local total_cost=$(grep -o '"cost_usd":[0-9.]*' "$log_file" 2>/dev/null | cut -d: -f2 | awk '{s+=$1} END {printf "%.3f", s+0}' || echo "0.000")

  local last_task=$(tail -1 "$log_file" | grep -o '"task":"[^"]*"' | head -1 | sed 's/"task":"//;s/"//')
  local last_date=$(tail -1 "$log_file" | grep -o '"date":"[^"]*"' | head -1 | sed 's/"date":"//;s/"//')

  cat > "$summary_file" <<EOF
task_count=${task_count}
success_count=${task_count}
success_rate=${success_rate}
streak=${streak}
total_cost=${total_cost}
last_task=${last_task}
last_date=${last_date}
EOF
}

# 태스크 완료 횟수 카운트 (forge-init, RANK_UP 제외)
growth_log_task_count() {
  local soul_name="$1"
  local summary_file="${GROWTH_DIR}/${soul_name}.summary"
  local log_file="${GROWTH_DIR}/${soul_name}.jsonl"

  if [ -f "$summary_file" ] && [ -f "$log_file" ] && [ "$summary_file" -nt "$log_file" ]; then
    grep '^task_count=' "$summary_file" | cut -d= -f2
    return
  fi

  if [ ! -f "$log_file" ]; then
    echo "0"
    return
  fi

  grep '"result":"success"' "$log_file" 2>/dev/null | grep -v '"task":"forge-init"' | grep -v '"task":"RANK_UP"' | grep -v '"task":"pack-install' | grep -v '"task":"forge-soul-create"' | wc -l | tr -d ' \r'
}

# 연속 무결함 카운트 (최근 연속으로 issues_found=0 또는 review_result=pass)
growth_log_streak() {
  local soul_name="$1"
  local summary_file="${GROWTH_DIR}/${soul_name}.summary"
  local log_file="${GROWTH_DIR}/${soul_name}.jsonl"
  local streak=0

  if [ -f "$summary_file" ] && [ -f "$log_file" ] && [ "$summary_file" -nt "$log_file" ]; then
    grep '^streak=' "$summary_file" | cut -d= -f2
    return
  fi

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
  local summary_file="${GROWTH_DIR}/${soul_name}.summary"
  local log_file="${GROWTH_DIR}/${soul_name}.jsonl"

  if [ -f "$summary_file" ] && [ -f "$log_file" ] && [ "$summary_file" -nt "$log_file" ]; then
    grep '^success_rate=' "$summary_file" | cut -d= -f2
    return
  fi

  if [ ! -f "$log_file" ]; then
    echo "0"
    return
  fi

  local total=$(grep '"task":' "$log_file" 2>/dev/null | grep -v '"task":"RANK_UP"' | grep -v '"task":"forge-init"' | grep -v '"task":"pack-install' | grep -v '"task":"forge-soul-create"' | wc -l | tr -d ' \r')
  total=${total:-0}

  if [ "$total" -eq 0 ]; then
    echo "100"
    return
  fi

  local success=$(grep '"result":"success"' "$log_file" 2>/dev/null | grep -v '"task":"RANK_UP"' | grep -v '"task":"forge-init"' | grep -v '"task":"pack-install' | grep -v '"task":"forge-soul-create"' | wc -l | tr -d ' \r')
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

# 숫자를 K 접미사로 포맷 (15000 → 15K, 1500 → 1.5K, 500 → 500)
_format_k() {
  local num="${1:-0}"
  if [ "$num" -ge 10000 ] 2>/dev/null; then
    echo "$((num / 1000))K"
  elif [ "$num" -ge 1000 ] 2>/dev/null; then
    local major=$((num / 1000))
    local minor=$(( (num % 1000) / 100 ))
    if [ "$minor" -gt 0 ]; then
      echo "${major}.${minor}K"
    else
      echo "${major}K"
    fi
  else
    echo "$num"
  fi
}

# SOUL의 총 비용 문자열 반환 ($X.XX)
_growth_log_total_cost() {
  local soul_name="$1"
  local summary_file="${GROWTH_DIR}/${soul_name}.summary"
  local log_file="${GROWTH_DIR}/${soul_name}.jsonl"

  if [ -f "$summary_file" ] && [ -f "$log_file" ] && [ "$summary_file" -nt "$log_file" ]; then
    grep '^total_cost=' "$summary_file" | cut -d= -f2
    return
  fi

  if [ ! -f "$log_file" ]; then
    echo "0.000"
    return
  fi
  grep -o '"cost_usd":[0-9.]*' "$log_file" 2>/dev/null | cut -d: -f2 | awk '{s+=$1} END {printf "%.3f", s+0}' || echo "0.000"
}

# 전체 SOUL 성장 대시보드
growth_log_dashboard() {
  echo "=== GolemGarden Growth Dashboard ==="
  echo ""
  printf "%-10s %-8s %-10s %-8s %-8s %s\n" "SOUL" "Tasks" "Rate" "Streak" "Cost" "Last Task"
  printf "%-10s %-8s %-10s %-8s %-8s %s\n" "----" "-----" "----" "------" "----" "---------"

  for log_file in "${GROWTH_DIR}"/*.jsonl; do
    [ -f "$log_file" ] || continue
    local name=$(basename "$log_file" .jsonl)
    local tasks=$(growth_log_task_count "$name")
    local rate=$(growth_log_success_rate "$name")
    local streak=$(growth_log_streak "$name")
    local cost=$(_growth_log_total_cost "$name")
    local last_task=$(tail -1 "$log_file" | grep -o '"task":"[^"]*"' | head -1 | sed 's/"task":"//;s/"//')

    printf "%-10s %-8s %-10s %-8s %-8s %s\n" "$name" "${tasks}건" "${rate}%" "${streak}연속" "\$${cost}" "$last_task"
  done
}

# SOUL별 비용 요약
growth_log_cost_summary() {
  local soul_name="$1"
  local log_file="${GROWTH_DIR}/${soul_name}.jsonl"

  if [ ! -f "$log_file" ]; then
    echo "[cost] ${soul_name}: 기록 없음"
    return
  fi

  local total_cost=$(_growth_log_total_cost "$soul_name")
  local task_count=$(growth_log_task_count "$soul_name")
  local tokens_in=$(grep -o '"tokens_in":[0-9]*' "$log_file" 2>/dev/null | cut -d: -f2 | awk '{s+=$1} END {print s+0}')
  local tokens_out=$(grep -o '"tokens_out":[0-9]*' "$log_file" 2>/dev/null | cut -d: -f2 | awk '{s+=$1} END {print s+0}')
  local tokens_cache=$(grep -o '"tokens_cache":[0-9]*' "$log_file" 2>/dev/null | cut -d: -f2 | awk '{s+=$1} END {print s+0}')

  local avg_cost="0.000"
  if [ "$task_count" -gt 0 ] 2>/dev/null; then
    avg_cost=$(echo "$total_cost $task_count" | awk '{printf "%.3f", $1/$2}')
  fi

  echo "=== ${soul_name} 비용 요약 ==="
  echo "  총 비용: \$${total_cost}"
  echo "  태스크: ${task_count}건"
  echo "  평균 비용/태스크: \$${avg_cost}"
  echo "  토큰: in=$(_format_k "$tokens_in") / out=$(_format_k "$tokens_out") / cache=$(_format_k "$tokens_cache")"
}

# 전체 비용 대시보드
growth_log_cost_dashboard() {
  echo "=== GolemGarden Cost Dashboard ==="
  echo ""
  printf "%-10s %-8s %-10s %-10s %-22s %s\n" "SOUL" "Tasks" "Total\$" "Avg\$/task" "Tokens(in/out/cache)" "Model"
  printf "%-10s %-8s %-10s %-10s %-22s %s\n" "----" "-----" "------" "---------" "--------------------" "-----"

  local grand_cost=0
  local grand_tasks=0
  local grand_in=0
  local grand_out=0
  local grand_cache=0

  for log_file in "${GROWTH_DIR}"/*.jsonl; do
    [ -f "$log_file" ] || continue
    local name=$(basename "$log_file" .jsonl)
    local tasks=$(growth_log_task_count "$name")
    local total_cost=$(_growth_log_total_cost "$name")
    local tokens_in=$(grep -o '"tokens_in":[0-9]*' "$log_file" 2>/dev/null | cut -d: -f2 | awk '{s+=$1} END {print s+0}')
    local tokens_out=$(grep -o '"tokens_out":[0-9]*' "$log_file" 2>/dev/null | cut -d: -f2 | awk '{s+=$1} END {print s+0}')
    local tokens_cache=$(grep -o '"tokens_cache":[0-9]*' "$log_file" 2>/dev/null | cut -d: -f2 | awk '{s+=$1} END {print s+0}')
    local model=$(grep -o '"model":"[^"]*"' "$log_file" 2>/dev/null | tail -1 | sed 's/"model":"//;s/"//')
    [ -z "$model" ] && model="—"

    local avg_cost="0.000"
    if [ "$tasks" -gt 0 ] 2>/dev/null; then
      avg_cost=$(echo "$total_cost $tasks" | awk '{printf "%.3f", $1/$2}')
    fi

    local token_str="$(_format_k "$tokens_in")/$(_format_k "$tokens_out")/$(_format_k "$tokens_cache")"

    printf "%-10s %-8s %-10s %-10s %-22s %s\n" "$name" "${tasks}건" "\$${total_cost}" "\$${avg_cost}" "$token_str" "$model"

    grand_cost=$(echo "$grand_cost $total_cost" | awk '{printf "%.3f", $1+$2}')
    grand_tasks=$((grand_tasks + tasks))
    grand_in=$((grand_in + tokens_in))
    grand_out=$((grand_out + tokens_out))
    grand_cache=$((grand_cache + tokens_cache))
  done

  local grand_avg="0.000"
  if [ "$grand_tasks" -gt 0 ]; then
    grand_avg=$(echo "$grand_cost $grand_tasks" | awk '{printf "%.3f", $1/$2}')
  fi
  local grand_token_str="$(_format_k "$grand_in")/$(_format_k "$grand_out")/$(_format_k "$grand_cache")"

  printf "%-10s %-8s %-10s %-10s %-22s %s\n" "---" "---" "---" "---" "---" "---"
  printf "%-10s %-8s %-10s %-10s %-22s %s\n" "Total" "${grand_tasks}건" "\$${grand_cost}" "\$${grand_avg}" "$grand_token_str" "—"
}
