#!/bin/bash
# dashboard-unified.sh — 통합 대시보드
# "한눈에" SOUL 팀 전체를 파악할 수 있는 단일 뷰.
# forge overview 명령으로 호출.
#
# 표시 내용:
#   1. 팀 요약 (총원, 활동, 비용, 성공률)
#   2. SOUL별 통합 현황 (랭크+성과+비용+최근 작업이 한 줄에)
#   3. 최근 활동 타임라인 (가장 최근 5건)
#   4. 승급 임박 / 주목할 점

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${GOLEM_ROOT}/lib/soul-parser.sh"
source "${GOLEM_ROOT}/lib/growth-log.sh"
source "${GOLEM_ROOT}/lib/rank-system.sh"

# 랭크 아이콘
_rank_icon() {
  case "$1" in
    novice) echo "N" ;;
    junior) echo "J" ;;
    senior) echo "S" ;;
    lead)   echo "L" ;;
    master) echo "M" ;;
    *)      echo "?" ;;
  esac
}

# 모델 축약
_model_short() {
  case "$1" in
    opus)   echo "Op" ;;
    sonnet) echo "So" ;;
    haiku)  echo "Ha" ;;
    *)      echo "$1" ;;
  esac
}

# 역할 축약 (6자 이내)
_role_short() {
  case "$1" in
    director)             echo "Dir" ;;
    backend-developer)    echo "Back" ;;
    frontend-developer)   echo "Front" ;;
    qa-tester)            echo "QA" ;;
    devops-engineer)      echo "DevOp" ;;
    data-analyst)         echo "Data" ;;
    technical-writer)     echo "Write" ;;
    security-auditor)     echo "Sec" ;;
    knowledge-auditor)    echo "Know" ;;
    game-logic-developer) echo "Game" ;;
    game-designer)        echo "GDsgn" ;;
    *)                    echo "$1" | cut -c1-5 ;;
  esac
}

# 추세 화살표 (최근 5건 vs 전체)
_trend_arrow() {
  local soul_name="$1"
  local log_file="${GROWTH_DIR}/${soul_name}.jsonl"
  [ ! -f "$log_file" ] && echo " " && return

  local total=$(grep '"result":"success"' "$log_file" 2>/dev/null | grep -v '"task":"RANK_UP"\|"task":"forge-init"\|"task":"pack-install' | wc -l | tr -d ' \r')
  local all_tasks=$(grep '"task":' "$log_file" 2>/dev/null | grep -v '"task":"RANK_UP"\|"task":"forge-init"\|"task":"pack-install' | wc -l | tr -d ' \r')
  [ "$all_tasks" -lt 3 ] && echo " " && return

  local rate=$(( total * 100 / all_tasks ))
  local recent=$(tail -5 "$log_file" | grep -c '"result":"success"' 2>/dev/null)
  local recent_total=$(tail -5 "$log_file" | grep -c '"result"' 2>/dev/null)
  [ "$recent_total" -eq 0 ] && echo " " && return
  local recent_rate=$(( recent * 100 / recent_total ))

  if [ "$recent_rate" -gt "$rate" ]; then echo "^"
  elif [ "$recent_rate" -lt "$rate" ]; then echo "v"
  else echo "="
  fi
}

# ── 메인 대시보드 ──

dashboard_unified() {
  local project_name=""
  if [ -n "${GOLEM_PROJECT:-}" ]; then
    project_name=$(basename "$GOLEM_PROJECT")
  fi

  # ── 헤더 ──
  echo ""
  echo "  GolemGarden${project_name:+ | ${project_name}}"
  echo "  $(date '+%Y-%m-%d %H:%M')"
  echo ""

  # ── 팀 요약 수집 ──
  local total_souls=0
  local active_souls=0
  local team_tasks=0
  local team_success=0
  local team_cost="0.000"
  local promotable=""

  # 데이터 수집 (한 번 순회)
  local soul_data=""
  while IFS= read -r soul_file; do
    [ -f "$soul_file" ] || continue
    soul_parse "$soul_file"
    total_souls=$((total_souls + 1))

    local name="$SOUL_NAME"
    local role="$SOUL_ROLE"
    local rank="$SOUL_RANK"
    local model="$SOUL_MODEL"

    # growth data
    local tasks=0 rate=100 streak=0 cost="0.000" last_task="-" last_date=""
    local log_file="${GROWTH_DIR}/${name}.jsonl"
    if [ -f "$log_file" ]; then
      local summary_file="${GROWTH_DIR}/${name}.summary"
      # summary 캐시 갱신
      _growth_log_update_summary "$name" 2>/dev/null

      if [ -f "$summary_file" ]; then
        tasks=$(grep '^task_count=' "$summary_file" | cut -d= -f2)
        rate=$(grep '^success_rate=' "$summary_file" | cut -d= -f2)
        streak=$(grep '^streak=' "$summary_file" | cut -d= -f2)
        cost=$(grep '^total_cost=' "$summary_file" | cut -d= -f2)
        last_task=$(grep '^last_task=' "$summary_file" | cut -d= -f2)
        # UTF-8 안전 자르기 (awk로 문자 단위)
        last_task=$(echo "$last_task" | awk '{print substr($0,1,18)}')
        last_date=$(grep '^last_date=' "$summary_file" | cut -d= -f2)
      fi

      tasks=${tasks:-0}
      [ "$tasks" -gt 0 ] && active_souls=$((active_souls + 1))
    fi

    team_tasks=$((team_tasks + tasks))
    team_success=$((team_success + tasks * rate / 100))
    team_cost=$(awk "BEGIN{printf \"%.3f\", ${team_cost} + ${cost}}")

    # 승급 임박 체크
    local total_tasks=$(_rank_total_task_count "$name" 2>/dev/null)
    local next_rank=$(rank_should_promote "$rank" "${total_tasks:-0}" "0" 2>/dev/null)
    [ -n "$next_rank" ] && promotable="${promotable}${name}(${rank}->${next_rank}) "

    local trend=$(_trend_arrow "$name")
    # 데이터 라인 저장
    soul_data="${soul_data}${name}|${role}|${rank}|${model}|${tasks}|${rate}|${streak}|${cost}|${last_task}|${last_date}|${trend}
"
  done < <(_all_soul_files)

  local team_rate=0
  [ "$team_tasks" -gt 0 ] && team_rate=$(( team_success * 100 / team_tasks ))

  # ── 팀 요약 출력 ──
  printf "  SOUL: %d명 (%d명 활동) | 태스크: %d건 | 성공률: %d%% | 비용: \$%s\n" \
    "$total_souls" "$active_souls" "$team_tasks" "$team_rate" "$team_cost"
  echo ""

  # ── SOUL 통합 테이블 ──
  # 활동 SOUL 먼저, 비활동 SOUL은 축약 표시
  printf "  %-8s %-5s %-2s %-2s %5s %4s %3s %8s  %s\n" \
    "SOUL" "Role" "Rk" "Md" "Tasks" "Rate" "Stk" "Cost" "Last Task"
  printf "  %-8s %-5s %-2s %-2s %5s %4s %3s %8s  %s\n" \
    "--------" "-----" "--" "--" "-----" "----" "---" "--------" "---------"

  # 활동 SOUL (tasks > 0) — 태스크 수 내림차순
  printf '%s' "$soul_data" | sort -t'|' -k5 -rn | while IFS='|' read -r name role rank model tasks rate streak cost last_task last_date trend; do
    [ -z "$name" ] && continue
    [ "$tasks" -eq 0 ] 2>/dev/null && continue

    local ri=$(_rank_icon "$rank")
    local ms=$(_model_short "$model")
    local rs=$(_role_short "$role")
    local streak_str=""
    [ "$streak" -gt 0 ] && streak_str="${streak}" || streak_str="-"

    printf "  %-8s %-5s %-2s %-2s %4s건 %3s%% %2s%s %7s  %s\n" \
      "$name" "$rs" "$ri" "$ms" "$tasks" "$rate" "$streak_str" "$trend" "\$${cost}" "$last_task"
  done

  # 비활동 SOUL (tasks == 0) — 한 줄로 축약
  printf '%s' "$soul_data" | while IFS='|' read -r name role rank model tasks rate streak cost last_task last_date trend; do
    [ -z "$name" ] && continue
    [ "$tasks" -gt 0 ] 2>/dev/null && continue
    printf "%s " "$name"
  done | {
    read -r inactive_list
    if [ -n "$inactive_list" ]; then
      echo ""
      echo "  (대기중: ${inactive_list})"
    fi
  }

  # ── 최근 활동 타임라인 (최근 5건) ──
  echo ""
  echo "  -- 최근 활동 --"

  local timeline=""
  for gdir in "${GOLEM_ROOT}/growth-log" "${GOLEM_PROJECT:+${GOLEM_PROJECT}/.golem/growth-log}"; do
    [ -z "$gdir" ] || [ ! -d "$gdir" ] && continue
    for lf in "${gdir}"/*.jsonl; do
      [ -f "$lf" ] || continue
      local sname=$(basename "$lf" .jsonl)
      tail -3 "$lf" 2>/dev/null | while IFS= read -r line; do
        [ -z "$line" ] && continue
        local date=$(echo "$line" | sed -n 's/.*"date":"\([^"]*\)".*/\1/p')
        local task=$(echo "$line" | sed -n 's/.*"task":"\([^"]*\)".*/\1/p')
        local result=$(echo "$line" | sed -n 's/.*"result":"\([^"]*\)".*/\1/p')
        [ -z "$date" ] && continue
        echo "${date}|${sname}|${task}|${result}"
      done
    done
  done | sort -t'|' -k1 -r | head -5 | while IFS='|' read -r date name task result; do
    [ -z "$date" ] && continue
    local icon="+"
    echo "$result" | grep -q "success" && icon="+"
    echo "$result" | grep -q "fail" && icon="x"
    echo "$result" | grep -q "RANK_UP\|novice.*junior\|junior.*senior" && icon="*"
    printf "  %s  %-8s  %s  %s\n" "$date" "$name" "$icon" "$(echo "$task" | awk '{print substr($0,1,40)}')"
  done

  # ── 주목할 점 ──
  local notes=""
  [ -n "$promotable" ] && notes="${notes}\n  >> 승급 임박: ${promotable}"

  # 지식 승격 대기
  local sync_file="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/sync/pending.jsonl"
  if [ -f "$sync_file" ]; then
    local pending=$(wc -l < "$sync_file" | tr -d ' \r')
    [ "$pending" -gt 0 ] && notes="${notes}\n  >> 지식 승격 대기: ${pending}건 (forge sync pending)"
  fi

  # 메일박스 미읽음
  local unread=0
  local mbox_dir="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/mailbox"
  if [ -d "$mbox_dir" ]; then
    for mf in "${mbox_dir}"/*.jsonl; do
      [ -f "$mf" ] || continue
      local u=$(grep -c '"status":"pending"' "$mf" 2>/dev/null)
      unread=$((unread + u))
    done
    [ "$unread" -gt 0 ] && notes="${notes}\n  >> 미읽음 메시지: ${unread}건 (forge mailbox dashboard)"
  fi

  if [ -n "$notes" ]; then
    echo ""
    echo "  -- 알림 --"
    printf '%b\n' "$notes"
  fi

  echo ""
}
