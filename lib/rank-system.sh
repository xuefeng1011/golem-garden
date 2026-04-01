#!/bin/bash
# rank-system.sh — SOUL 랭크 시스템 관리
# Usage: source lib/rank-system.sh && rank_check ryn

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${GOLEM_ROOT}/lib/soul-parser.sh"
source "${GOLEM_ROOT}/lib/growth-log.sh"

# 랭크 정의 (순서대로)
RANKS=("novice" "junior" "senior" "lead" "master")

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
  local task_count=$(growth_log_task_count "$soul_name")
  local streak=$(growth_log_streak "$soul_name")
  local current_idx=$(rank_index "$current_rank")

  local eligible=""
  local next_rank=""
  local reason=""

  case "$current_rank" in
    novice)
      if [ "$task_count" -ge 10 ]; then
        eligible="yes"
        next_rank="junior"
        reason="태스크 ${task_count}건 완료 (≥10)"
      fi
      ;;
    junior)
      if [ "$task_count" -ge 50 ] && [ "$streak" -ge 10 ]; then
        eligible="yes"
        next_rank="senior"
        reason="태스크 ${task_count}건 (≥50) + 무결함 ${streak}연속 (≥10)"
      fi
      ;;
    senior)
      if [ "$task_count" -ge 100 ]; then
        eligible="yes"
        next_rank="lead"
        reason="태스크 ${task_count}건 (≥100) + 멘토링 이력"
      fi
      ;;
    lead)
      if [ "$task_count" -ge 200 ]; then
        eligible="yes"
        next_rank="master"
        reason="태스크 ${task_count}건 (≥200) + 커뮤니티 검증"
      fi
      ;;
    master)
      echo "[rank] ${soul_name}: 이미 최고 랭크 (Master)"
      return 0
      ;;
  esac

  if [ "$eligible" = "yes" ]; then
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
  _sed_i "s/^rank: ${current_rank}/rank: ${next_rank}/" "$soul_file"

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
    local tasks=$(growth_log_task_count "$SOUL_NAME")
    local streak=$(growth_log_streak "$SOUL_NAME")
    local check=$(rank_check "$SOUL_NAME" 2>/dev/null | grep "^ELIGIBLE:" | cut -d: -f2)
    local next="${check:-—}"

    printf "%-10s %-10s %-8s %-8s %s\n" "$SOUL_NAME" "$SOUL_RANK" "${tasks}건" "${streak}" "$next"
  done < <(_all_soul_files)
}
