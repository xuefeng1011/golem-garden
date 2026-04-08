#!/bin/bash
# rank-system.sh — SOUL 랭크 시스템 관리
# Usage: source lib/rank-system.sh && rank_check ryn

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${GOLEM_ROOT}/lib/soul-parser.sh"
source "${GOLEM_ROOT}/lib/growth-log.sh"

# 랭크 정의 (순서대로)
RANKS=("novice" "junior" "senior" "lead" "master")

# 전체 프로젝트 합산 태스크 수 (글로벌 대시보드와 동일 로직)
_rank_total_task_count() {
  local soul_name="$1"
  local saved_growth="$GROWTH_DIR"
  local total=0

  # 1) 글로벌 growth-log (서브셸로 GROWTH_DIR 오염 방지)
  local g=$(GROWTH_DIR="${GOLEM_ROOT}/growth-log" growth_log_task_count "$soul_name")
  total=$((total + g))

  # 2) 등록된 프로젝트별 .golem/growth-log
  local projects_file="${GOLEM_ROOT}/projects.jsonl"
  if [ -f "$projects_file" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      local proj_path=$(echo "$line" | grep -o '"path":"[^"]*"' | sed 's/"path":"//;s/"//')
      [ -z "$proj_path" ] && continue
      local proj_growth="${proj_path}/.golem/growth-log"
      if [ -f "${proj_growth}/${soul_name}.jsonl" ]; then
        local p=$(GROWTH_DIR="$proj_growth" growth_log_task_count "$soul_name")
        total=$((total + p))
      fi
    done < "$projects_file"
  fi
  echo "$total"
}

# 전체 프로젝트 합산 streak
_rank_total_streak() {
  local soul_name="$1"
  local saved_growth="$GROWTH_DIR"
  local max_streak=0

  # 글로벌 (서브셸로 GROWTH_DIR 오염 방지)
  local s=$(GROWTH_DIR="${GOLEM_ROOT}/growth-log" growth_log_streak "$soul_name")
  [ "$s" -gt "$max_streak" ] 2>/dev/null && max_streak=$s

  # 프로젝트별
  local projects_file="${GOLEM_ROOT}/projects.jsonl"
  if [ -f "$projects_file" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      local proj_path=$(echo "$line" | grep -o '"path":"[^"]*"' | sed 's/"path":"//;s/"//')
      [ -z "$proj_path" ] && continue
      local proj_growth="${proj_path}/.golem/growth-log"
      if [ -f "${proj_growth}/${soul_name}.jsonl" ]; then
        s=$(GROWTH_DIR="$proj_growth" growth_log_streak "$soul_name")
        [ "$s" -gt "$max_streak" ] 2>/dev/null && max_streak=$s
      fi
    done < "$projects_file"
  fi
  echo "$max_streak"
}

rank_should_promote() {
  local current_rank="$1"
  local task_count="$2"
  local streak="$3"

  case "$current_rank" in
    novice)  [ "$task_count" -ge 10 ] && echo "junior" ;;
    junior)  [ "$task_count" -ge 50 ] && [ "$streak" -ge 10 ] && echo "senior" ;;
    senior)  [ "$task_count" -ge 100 ] && echo "lead" ;;
    lead)    [ "$task_count" -ge 200 ] && echo "master" ;;
  esac
}

# 랭크 인덱스 반환
rank_index() {
  local rank="$1"
  case "$rank" in
    novice) echo 0 ;;
    junior) echo 1 ;;
    senior) echo 2 ;;
    lead)   echo 3 ;;
    master) echo 4 ;;
    *)      echo 0 ;;
  esac
}

# 랭크 승급 조건 확인
rank_check() {
  local soul_name="$1"
  local soul_file=$(_resolve_soul_file "$soul_name")

  soul_parse "$soul_file"
  local current_rank="$SOUL_RANK"
  local task_count=$(_rank_total_task_count "$soul_name")
  local streak=$(_rank_total_streak "$soul_name")
  local current_idx=$(rank_index "$current_rank")

  local next_rank=""
  local reason=""

  if [ "$current_rank" = "master" ]; then
    echo "[rank] ${soul_name}: 이미 최고 랭크 (Master)"
    return 0
  fi

  next_rank=$(rank_should_promote "$current_rank" "$task_count" "$streak")

  if [ -n "$next_rank" ]; then
    case "$current_rank" in
      novice) reason="전체 프로젝트 태스크 ${task_count}건 완료 (≥10)" ;;
      junior) reason="전체 프로젝트 태스크 ${task_count}건 (≥50) + 무결함 ${streak}연속 (≥10)" ;;
      senior) reason="전체 프로젝트 태스크 ${task_count}건 (≥100) + 멘토링 이력" ;;
      lead)   reason="전체 프로젝트 태스크 ${task_count}건 (≥200) + 커뮤니티 검증" ;;
    esac
  fi

  if [ -n "$next_rank" ]; then
    echo "[rank] ${soul_name}: 승급 가능! ${current_rank} → ${next_rank} (${reason})"
    echo "ELIGIBLE:${next_rank}:${reason}"
  else
    echo "[rank] ${soul_name}: ${current_rank} 유지 (tasks=${task_count}, streak=${streak})"
  fi
}

# 랭크 승급 실행 (SOUL.md 업데이트 + growth-log 기록)
rank_promote() {
  local soul_name="$1"
  local soul_file=$(_resolve_soul_file "$soul_name")

  soul_parse "$soul_file"
  local current_rank="$SOUL_RANK"

  local check_result=$(rank_check "$soul_name" | grep "^ELIGIBLE:")
  if [ -z "$check_result" ]; then
    echo "[rank] ${soul_name}: 승급 조건 미충족"
    return 1
  fi

  local next_rank=$(echo "$check_result" | cut -d: -f2)
  local reason=$(echo "$check_result" | cut -d: -f3-)

  # SOUL.md에서 rank 필드 업데이트
  _sed_i "s/^rank:[[:space:]]*.*/rank: ${next_rank}/" "$soul_file"

  # growth-log에 승급 이벤트 기록
  growth_log_rank_up "$soul_name" "$current_rank" "$next_rank" "$reason"

  echo "[rank] ${soul_name}: 승급 완료! ${current_rank} → ${next_rank}"
}

# SOUL의 현재 권한 범위 확인
rank_permissions() {
  local rank="$1"
  case "$rank" in
    novice)
      echo "single_file_edit=yes multi_file_edit=no auto_review=required architecture=no delegation=no"
      ;;
    junior)
      echo "single_file_edit=yes multi_file_edit=yes auto_review=required architecture=no delegation=no"
      ;;
    senior)
      echo "single_file_edit=yes multi_file_edit=yes auto_review=optional architecture=yes delegation=no"
      ;;
    lead)
      echo "single_file_edit=yes multi_file_edit=yes auto_review=optional architecture=yes delegation=yes"
      ;;
    master)
      echo "single_file_edit=yes multi_file_edit=yes auto_review=exempt architecture=yes delegation=yes"
      ;;
  esac
}

# 랭크 상태 대시보드
rank_dashboard() {
  echo "=== GolemGarden Rank Dashboard ==="
  echo ""
  printf "%-10s %-10s %-8s %-8s %s\n" "SOUL" "Rank" "Tasks" "Streak" "Next Rank"
  printf "%-10s %-10s %-8s %-8s %s\n" "----" "----" "-----" "------" "---------"

  while IFS= read -r soul_file; do
    [ -f "$soul_file" ] || continue
    soul_parse "$soul_file"
    local tasks=$(_rank_total_task_count "$SOUL_NAME")
    local streak=$(_rank_total_streak "$SOUL_NAME")
    local check=$(rank_check "$SOUL_NAME" 2>/dev/null | grep "^ELIGIBLE:" | cut -d: -f2)
    local next="${check:-—}"

    printf "%-10s %-10s %-8s %-8s %s\n" "$SOUL_NAME" "$SOUL_RANK" "${tasks}건" "${streak}" "$next"
  done < <(_all_soul_files)
}
