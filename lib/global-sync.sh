#!/bin/bash
# global-sync.sh — 프로젝트-글로벌 데이터 동기화
# 등록된 모든 프로젝트의 growth-log를 합산하여 글로벌 랭크/업적/케미를 갱신
# 프로젝트 SOUL에 랭크를 역전파
# Usage: source lib/global-sync.sh && global_sync

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${GOLEM_ROOT}/lib/soul-parser.sh"
source "${GOLEM_ROOT}/lib/growth-log.sh"
source "${GOLEM_ROOT}/lib/rank-system.sh"

# 등록된 프로젝트 목록 파일
PROJECTS_FILE="${GOLEM_ROOT}/projects.jsonl"

# 등록된 프로젝트 경로 반환
_sync_project_paths() {
  [ ! -f "$PROJECTS_FILE" ] && return
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local path=$(echo "$line" | grep -o '"path":"[^"]*"' | sed 's/"path":"//;s/"//')
    [ -d "${path}/.golem" ] && echo "$path"
  done < "$PROJECTS_FILE"
}

# ─────────────────────────────────────────────────────────
# 메인 동기화
# ─────────────────────────────────────────────────────────

global_sync() {
  echo "=== GolemGarden Global Sync ==="
  echo ""

  # 등록된 프로젝트 수
  local project_count=0
  while IFS= read -r p; do [ -n "$p" ] && project_count=$((project_count+1)); done < <(_sync_project_paths)

  if [ "$project_count" -eq 0 ]; then
    echo "[sync] 등록된 프로젝트 없음. forge dashboard global-register로 등록하세요."
    return 1
  fi

  echo "[sync] 등록 프로젝트: ${project_count}개"
  echo ""

  # SOUL별로 동기화
  local synced=0
  local promoted=0

  for soul_file in "${GOLEM_ROOT}/souls/"*.md; do
    [ -f "$soul_file" ] || continue
    local name=$(basename "$soul_file" .md)

    local result=$(_sync_soul "$name")
    synced=$((synced + 1))

    # 승급 발생 여부
    echo "$result" | grep -q "RANK_UP" && promoted=$((promoted + 1))
  done

  echo ""
  echo "=== Sync 완료 ==="
  echo "  동기화 SOUL: ${synced}개"
  echo "  랭크 승급:   ${promoted}건"
  echo ""

  # 글로벌 대시보드 갱신
  if [ -f "${GOLEM_ROOT}/lib/dashboard-global.sh" ]; then
    source "${GOLEM_ROOT}/lib/dashboard-global.sh"
    dashboard_global_refresh 2>/dev/null
    echo "[sync] 글로벌 대시보드 갱신 완료"
  fi
}

# 개별 SOUL 동기화
_sync_soul() {
  local soul_name="$1"
  local global_log="${GOLEM_ROOT}/growth-log/${soul_name}.jsonl"

  echo "[sync] ${soul_name}: 동기화 시작"

  # ─── Step 1: 프로젝트별 태스크 합산 ───
  local total_tasks=0
  local total_streak=0
  local best_streak=0
  local total_cost="0.000"

  # 글로벌 기존 태스크 수 (forge-init, RANK_UP 제외)
  local g_tasks=0
  if [ -f "$global_log" ]; then
    g_tasks=$(grep '"result":"success"' "$global_log" 2>/dev/null | grep -v '"task":"forge-init"' | grep -v '"task":"RANK_UP"' | grep -v '"task":"pack-install' | grep -v '"task":"forge-soul-create"' | wc -l | tr -d ' \r')
  fi
  g_tasks=${g_tasks:-0}
  total_tasks=$g_tasks

  # 프로젝트별 합산
  while IFS= read -r proj_path; do
    [ -z "$proj_path" ] && continue
    local proj_log="${proj_path}/.golem/growth-log/${soul_name}.jsonl"
    [ ! -f "$proj_log" ] && continue

    local p_tasks=$(grep '"result":"success"' "$proj_log" 2>/dev/null | grep -v '"task":"forge-init"' | grep -v '"task":"RANK_UP"' | grep -v '"task":"pack-install' | grep -v '"task":"forge-soul-create"' | wc -l | tr -d ' \r')
    p_tasks=${p_tasks:-0}
    total_tasks=$((total_tasks + p_tasks))

    # 프로젝트별 streak
    local saved_growth="$GROWTH_DIR"
    GROWTH_DIR="${proj_path}/.golem/growth-log"
    local p_streak=$(growth_log_streak "$soul_name")
    GROWTH_DIR="$saved_growth"
    [ "$p_streak" -gt "$best_streak" ] && best_streak=$p_streak

    # 프로젝트별 비용
    local p_cost=$(grep -o '"cost_usd":[0-9.]*' "$proj_log" 2>/dev/null | cut -d: -f2 | awk '{s+=$1} END {printf "%.3f", s+0}')
    total_cost=$(echo "$total_cost $p_cost" | awk '{printf "%.3f", $1+$2}')

    local proj_name=$(basename "$proj_path")
    echo "  ${proj_name}: +${p_tasks} tasks, streak=${p_streak}"
  done < <(_sync_project_paths)

  # 글로벌 streak과 비교
  local g_streak=0
  if [ -f "$global_log" ]; then
    local saved_growth="$GROWTH_DIR"
    GROWTH_DIR="${GOLEM_ROOT}/growth-log"
    g_streak=$(growth_log_streak "$soul_name")
    GROWTH_DIR="$saved_growth"
  fi
  [ "$g_streak" -gt "$best_streak" ] && best_streak=$g_streak

  echo "  합산: tasks=${total_tasks}, best_streak=${best_streak}, cost=\$${total_cost}"

  # ─── Step 2: 글로벌 랭크 판정 (합산 기준) ───
  local soul_file="${GOLEM_ROOT}/souls/${soul_name}.md"
  [ ! -f "$soul_file" ] && return

  soul_parse "$soul_file"
  local current_rank="$SOUL_RANK"
  local new_rank="$current_rank"

  # 합산 기준 랭크 판정
  case "$current_rank" in
    novice)
      [ "$total_tasks" -ge 10 ] && new_rank="junior"
      ;;
    junior)
      [ "$total_tasks" -ge 50 ] && [ "$best_streak" -ge 10 ] && new_rank="senior"
      ;;
    senior)
      [ "$total_tasks" -ge 100 ] && new_rank="lead"
      ;;
    lead)
      [ "$total_tasks" -ge 200 ] && new_rank="master"
      ;;
  esac

  # ─── Step 3: 랭크 변경 시 글로벌 + 프로젝트 역전파 ───
  if [ "$new_rank" != "$current_rank" ]; then
    echo "  ** 랭크 승급: ${current_rank} -> ${new_rank} (합산 ${total_tasks}건, streak ${best_streak}) **"

    # 글로벌 SOUL 랭크 업데이트
    _sed_i "s/^rank: ${current_rank}/rank: ${new_rank}/" "$soul_file"

    # 글로벌 growth-log에 승급 이벤트 기록
    local date=$(date +%Y-%m-%d)
    echo "{\"date\":\"${date}\",\"task\":\"RANK_UP\",\"result\":\"${current_rank}->${new_rank}\",\"trigger\":\"global_sync(tasks=${total_tasks},streak=${best_streak})\"}" >> "$global_log"

    # 프로젝트별 SOUL에도 랭크 역전파
    while IFS= read -r proj_path; do
      [ -z "$proj_path" ] && continue
      local proj_soul="${proj_path}/.golem/souls/${soul_name}.md"
      if [ -f "$proj_soul" ]; then
        _sed_i "s/^rank: ${current_rank}/rank: ${new_rank}/" "$proj_soul"

        # tools도 랭크에 맞게 갱신
        _sync_update_tools "$proj_soul" "$new_rank" "$SOUL_ROLE"

        local proj_name=$(basename "$proj_path")
        echo "  -> ${proj_name}/.golem/souls/${soul_name}.md 역전파 완료"
      fi
    done < <(_sync_project_paths)

    # 글로벌 SOUL tools도 갱신
    _sync_update_tools "$soul_file" "$new_rank" "$SOUL_ROLE"

    echo "RANK_UP"
  else
    echo "  랭크 유지: ${current_rank} (tasks=${total_tasks}, streak=${best_streak})"
  fi

  # ─── Step 4: 글로벌 업적 체크 ───
  if [ -f "${GOLEM_ROOT}/lib/achievement.sh" ]; then
    # 임시로 GROWTH_DIR을 글로벌로 설정하고 체크
    # 업적은 합산 기준으로 체크해야 하므로 가상 카운트 사용
    local ach_file="${GOLEM_ROOT}/achievements.jsonl"
    local date=$(date +%Y-%m-%d)

    # 태스크 수 기반 업적 (합산)
    _sync_ach_try "$soul_name" "tasks_10" "Getting Started" "total tasks >= 10" "$((total_tasks >= 10))" "$ach_file"
    _sync_ach_try "$soul_name" "tasks_50" "Veteran" "total tasks >= 50" "$((total_tasks >= 50))" "$ach_file"
    _sync_ach_try "$soul_name" "tasks_100" "Centurion" "total tasks >= 100" "$((total_tasks >= 100))" "$ach_file"
    _sync_ach_try "$soul_name" "tasks_200" "Grandmaster" "total tasks >= 200" "$((total_tasks >= 200))" "$ach_file"

    # streak 기반 업적 (best)
    _sync_ach_try "$soul_name" "streak_5" "Hot Streak" "best streak >= 5" "$((best_streak >= 5))" "$ach_file"
    _sync_ach_try "$soul_name" "streak_10" "Streak Master" "best streak >= 10" "$((best_streak >= 10))" "$ach_file"
    _sync_ach_try "$soul_name" "streak_20" "Untouchable" "best streak >= 20" "$((best_streak >= 20))" "$ach_file"

    # 멀티 프로젝트 업적
    local active_projects=0
    while IFS= read -r proj_path; do
      [ -z "$proj_path" ] && continue
      [ -f "${proj_path}/.golem/growth-log/${soul_name}.jsonl" ] && active_projects=$((active_projects + 1))
    done < <(_sync_project_paths)
    _sync_ach_try "$soul_name" "polyglot" "Polyglot" "3+ projects" "$((active_projects >= 3))" "$ach_file"
  fi

  # ─── Step 5: 케미 데이터 글로벌 집계 ───
  _sync_chemistry "$soul_name"
}

# 업적 체크 헬퍼 (글로벌)
_sync_ach_try() {
  local soul="$1" id="$2" name="$3" desc="$4" condition="$5" file="$6"
  [ "$condition" -eq 0 ] 2>/dev/null && return
  [ -f "$file" ] && grep -q "\"soul\":\"${soul}\".*\"id\":\"${id}\"" "$file" 2>/dev/null && return
  local date=$(date +%Y-%m-%d)
  echo "{\"date\":\"${date}\",\"soul\":\"${soul}\",\"id\":\"${id}\",\"name\":\"${name}\",\"desc\":\"${desc}\"}" >> "$file"
  echo "  [achievement] ${soul}: ${name} -- ${desc}"
}

# 랭크 변경 시 tools 필드 업데이트
_sync_update_tools() {
  local soul_file="$1"
  local new_rank="$2"
  local role="$3"

  local new_tools=""
  if [ "$role" = "director" ]; then
    new_tools="[Agent, SendMessage, TaskCreate, TaskStop, Read, Grep, Glob]"
  else
    case "$new_rank" in
      novice) new_tools="[Read, Edit, Grep, Glob]" ;;
      junior) new_tools="[Read, Edit, Write, Bash, Grep, Glob]" ;;
      senior) new_tools="[Read, Edit, Write, Bash, Grep, Glob, Agent, WebFetch]" ;;
      lead)   new_tools="[Read, Edit, Write, Bash, Grep, Glob, Agent, WebFetch, SendMessage]" ;;
      master) new_tools="[Read, Edit, Write, Bash, Grep, Glob, Agent, WebFetch, SendMessage, TaskCreate]" ;;
    esac
  fi

  [ -n "$new_tools" ] && _sed_i "s/^tools: \[.*\]/tools: ${new_tools}/" "$soul_file"

  # maxTurns도 갱신
  local new_turns=""
  case "$new_rank" in
    novice) new_turns=15 ;; junior) new_turns=25 ;; senior) new_turns=40 ;;
    lead)   new_turns=60 ;; master) new_turns=80 ;;
  esac
  [ "$role" = "director" ] && new_turns=50
  [ -n "$new_turns" ] && _sed_i "s/^maxTurns: [0-9]*/maxTurns: ${new_turns}/" "$soul_file"

  # isolation도 갱신
  local new_iso="none"
  case "$new_rank" in
    senior|lead|master) new_iso="worktree" ;;
  esac
  [ "$role" = "director" ] && new_iso="none"
  [ "$role" = "qa-tester" ] && new_iso="none"
  _sed_i "s/^isolation: .*/isolation: ${new_iso}/" "$soul_file"
}

# 케미 데이터 프로젝트 → 글로벌 집계
_sync_chemistry() {
  local soul_name="$1"
  local global_chem="${GOLEM_ROOT}/chemistry.jsonl"

  while IFS= read -r proj_path; do
    [ -z "$proj_path" ] && continue
    local proj_chem="${proj_path}/.golem/chemistry.jsonl"
    [ ! -f "$proj_chem" ] && continue

    # 해당 SOUL이 포함된 케미 레코드를 글로벌에 복사 (중복 방지: 날짜+pair 기준)
    grep "\"${soul_name}\"" "$proj_chem" 2>/dev/null | while IFS= read -r line; do
      [ -z "$line" ] && continue
      local pair=$(echo "$line" | grep -o '"pair":"[^"]*"' | sed 's/"pair":"//;s/"//')
      local date=$(echo "$line" | grep -o '"date":"[^"]*"' | sed 's/"date":"//;s/"//')

      # 같은 날짜+pair 조합이 글로벌에 없으면 추가
      if [ ! -f "$global_chem" ] || ! grep -q "\"pair\":\"${pair}\".*\"date\":\"${date}\"" "$global_chem" 2>/dev/null; then
        echo "$line" >> "$global_chem"
      fi
    done
  done < <(_sync_project_paths)
}

# ─────────────────────────────────────────────────────────
# 동기화 상태 확인
# ─────────────────────────────────────────────────────────

global_sync_status() {
  echo "=== GolemGarden Sync Status ==="
  echo ""

  printf "%-10s %-8s %-10s %-10s %-10s %-10s %s\n" "SOUL" "Rank" "Global" "Projects" "Total" "Streak" "Next"
  printf "%-10s %-8s %-10s %-10s %-10s %-10s %s\n" "----" "----" "------" "--------" "-----" "------" "----"

  for soul_file in "${GOLEM_ROOT}/souls/"*.md; do
    [ -f "$soul_file" ] || continue
    local name=$(basename "$soul_file" .md)
    soul_parse "$soul_file"

    # 글로벌 태스크
    local saved_growth="$GROWTH_DIR"
    GROWTH_DIR="${GOLEM_ROOT}/growth-log"
    local g_tasks=$(growth_log_task_count "$name")
    local g_streak=$(growth_log_streak "$name")
    GROWTH_DIR="$saved_growth"

    # 프로젝트별 태스크 합산
    local p_tasks=0
    local best_streak=$g_streak
    while IFS= read -r proj_path; do
      [ -z "$proj_path" ] && continue
      local proj_log="${proj_path}/.golem/growth-log/${name}.jsonl"
      [ ! -f "$proj_log" ] && continue
      local pt=$(grep '"result":"success"' "$proj_log" 2>/dev/null | grep -v '"task":"forge-init"' | grep -v '"task":"RANK_UP"' | grep -v '"task":"pack-install' | grep -v '"task":"forge-soul-create"' | wc -l | tr -d ' \r')
      p_tasks=$((p_tasks + pt))
      GROWTH_DIR="${proj_path}/.golem/growth-log"
      local ps=$(growth_log_streak "$name")
      GROWTH_DIR="$saved_growth"
      [ "$ps" -gt "$best_streak" ] && best_streak=$ps
    done < <(_sync_project_paths)

    local total=$((g_tasks + p_tasks))

    # 다음 랭크까지
    local next=""
    case "$SOUL_RANK" in
      novice) next="Jr@10 ($(( total * 100 / 10 ))%)" ;;
      junior) next="Sr@50 ($(( total * 100 / 50 ))%)" ;;
      senior) next="Ld@100 ($(( total * 100 / 100 ))%)" ;;
      lead)   next="Ms@200 ($(( total * 100 / 200 ))%)" ;;
      master) next="MAX" ;;
    esac

    printf "%-10s %-8s %-10s %-10s %-10s %-10s %s\n" "$SOUL_NAME" "$SOUL_RANK" "${g_tasks}" "${p_tasks}" "${total}" "${best_streak}" "$next"
  done
}
