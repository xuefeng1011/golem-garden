#!/bin/bash
# achievement.sh — 업적/뱃지 시스템
# SOUL이 이정표를 달성하면 뱃지를 획득
# Usage: source lib/achievement.sh && achievement_check ryn

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${GOLEM_ROOT}/lib/soul-parser.sh"
source "${GOLEM_ROOT}/lib/growth-log.sh"

# 업적 저장 파일
ACHIEVEMENT_FILE="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/achievements.jsonl"

# ─────────────────────────────────────────────────────────
# 업적 정의 (ID, 이름, 아이콘, 조건, 설명)
# ─────────────────────────────────────────────────────────

# 업적 달성 체크 + 새 달성 시 기록
# achievement_check <soul_name>
achievement_check() {
  local soul_name="$1"
  local soul_file=$(_resolve_soul_file "$soul_name")
  [ ! -f "$soul_file" ] && return

  soul_parse "$soul_file"
  local tasks=$(growth_log_task_count "$soul_name")
  local streak=$(growth_log_streak "$soul_name")
  local rate=$(growth_log_success_rate "$soul_name")

  local log_file="${GROWTH_DIR:-${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/growth-log}/${soul_name}.jsonl"
  local reviews=0
  [ -f "$log_file" ] && reviews=$(grep -c '"reviewer"' "$log_file" 2>/dev/null | tr -d ' \r')
  reviews=${reviews:-0}

  # 리뷰어로서 참여한 횟수
  local as_reviewer=0
  for lf in "${GROWTH_DIR:-${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/growth-log}"/*.jsonl; do
    [ -f "$lf" ] || continue
    local cnt=$(grep "\"reviewer\":\"${soul_name}\"" "$lf" 2>/dev/null | wc -l | tr -d ' \r')
    as_reviewer=$((as_reviewer + cnt))
  done

  mkdir -p "$(dirname "$ACHIEVEMENT_FILE")"

  # 각 업적 체크
  _ach_try "$soul_name" "first_blood"    "First Blood"      "첫 태스크 성공"              "$((tasks >= 1))"
  _ach_try "$soul_name" "streak_5"       "Hot Streak"       "무결함 5연속"                "$((streak >= 5))"
  _ach_try "$soul_name" "streak_10"      "Streak Master"    "무결함 10연속"               "$((streak >= 10))"
  _ach_try "$soul_name" "streak_20"      "Untouchable"      "무결함 20연속"               "$((streak >= 20))"
  _ach_try "$soul_name" "tasks_10"       "Getting Started"  "태스크 10회 완료"            "$((tasks >= 10))"
  _ach_try "$soul_name" "tasks_50"       "Veteran"          "태스크 50회 완료"            "$((tasks >= 50))"
  _ach_try "$soul_name" "tasks_100"      "Centurion"        "태스크 100회 완료"           "$((tasks >= 100))"
  _ach_try "$soul_name" "tasks_200"      "Grandmaster"      "태스크 200회 완료"           "$((tasks >= 200))"
  _ach_try "$soul_name" "perfect_rate"   "Perfectionist"    "성공률 100% (10건 이상)"     "$(( rate == 100 && tasks >= 10 ))"
  _ach_try "$soul_name" "reviewer_5"     "Code Inspector"   "리뷰어 5회 참여"             "$((as_reviewer >= 5))"
  _ach_try "$soul_name" "reviewer_20"    "Mentor"           "리뷰어 20회 참여"            "$((as_reviewer >= 20))"
  _ach_try "$soul_name" "reviewed_10"    "Reviewed Veteran" "리뷰 10회 받음"              "$((reviews >= 10))"
  _ach_try "$soul_name" "rank_junior"    "Promoted!"        "Junior 승급"                 "$([ "$SOUL_RANK" != "novice" ] && echo 1 || echo 0)"
  _ach_try "$soul_name" "rank_senior"    "Expert"           "Senior 승급"                 "$(echo "$SOUL_RANK" | grep -qE 'senior|lead|master' && echo 1 || echo 0)"
  _ach_try "$soul_name" "rank_master"    "Grandmaster"      "Master 도달"                 "$([ "$SOUL_RANK" = "master" ] && echo 1 || echo 0)"
}

# 내부: 업적 달성 시도 (중복 방지)
_ach_try() {
  local soul_name="$1"
  local ach_id="$2"
  local ach_name="$3"
  local ach_desc="$4"
  local condition="$5"

  # 조건 미충족
  [ "$condition" -eq 0 ] 2>/dev/null && return

  # 이미 달성했는지 확인
  if [ -f "$ACHIEVEMENT_FILE" ] && grep -q "\"soul\":\"${soul_name}\".*\"id\":\"${ach_id}\"" "$ACHIEVEMENT_FILE" 2>/dev/null; then
    return  # 이미 보유
  fi

  # 새 업적 달성!
  local date=$(date +%Y-%m-%d)
  echo "{\"date\":\"${date}\",\"soul\":\"${soul_name}\",\"id\":\"${ach_id}\",\"name\":\"${ach_name}\",\"desc\":\"${ach_desc}\"}" >> "$ACHIEVEMENT_FILE"
  echo "[achievement] ${soul_name}: ${ach_name} 달성! — ${ach_desc}"
}

# 업적 아이콘 매핑
_ach_icon() {
  local ach_id="$1"
  case "$ach_id" in
    first_blood)    echo "+" ;;
    streak_5)       echo "*" ;;
    streak_10)      echo "**" ;;
    streak_20)      echo "***" ;;
    tasks_10)       echo "#10" ;;
    tasks_50)       echo "#50" ;;
    tasks_100)      echo "#100" ;;
    tasks_200)      echo "#200" ;;
    perfect_rate)   echo "100%" ;;
    reviewer_5)     echo "R5" ;;
    reviewer_20)    echo "R20" ;;
    reviewed_10)    echo "rv10" ;;
    rank_junior)    echo "Jr" ;;
    rank_senior)    echo "Sr" ;;
    rank_master)    echo "Ms" ;;
    *)              echo "?" ;;
  esac
}

# SOUL의 보유 업적 목록
# achievement_list <soul_name>
achievement_list() {
  local soul_name="$1"

  if [ ! -f "$ACHIEVEMENT_FILE" ]; then
    echo "[achievement] ${soul_name}: 업적 없음"
    return
  fi

  local achievements=$(grep "\"soul\":\"${soul_name}\"" "$ACHIEVEMENT_FILE" 2>/dev/null)
  if [ -z "$achievements" ]; then
    echo "[achievement] ${soul_name}: 업적 없음"
    return
  fi

  local count=$(echo "$achievements" | wc -l | tr -d ' \r')
  echo "=== ${soul_name} Achievements (${count}개) ==="
  echo ""

  echo "$achievements" | while IFS= read -r line; do
    [ -z "$line" ] && continue
    local name=$(echo "$line" | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"//')
    local desc=$(echo "$line" | grep -o '"desc":"[^"]*"' | sed 's/"desc":"//;s/"//')
    local date=$(echo "$line" | grep -o '"date":"[^"]*"' | sed 's/"date":"//;s/"//')
    local id=$(echo "$line" | grep -o '"id":"[^"]*"' | sed 's/"id":"//;s/"//')
    local icon=$(_ach_icon "$id")
    echo "  [${icon}] ${name} — ${desc} (${date})"
  done
}

# SOUL의 뱃지 요약 (한 줄, forge status용)
# achievement_badges <soul_name>
achievement_badges() {
  local soul_name="$1"

  if [ ! -f "$ACHIEVEMENT_FILE" ]; then
    echo ""
    return
  fi

  local badges=""
  grep "\"soul\":\"${soul_name}\"" "$ACHIEVEMENT_FILE" 2>/dev/null | while IFS= read -r line; do
    local id=$(echo "$line" | grep -o '"id":"[^"]*"' | sed 's/"id":"//;s/"//')
    local icon=$(_ach_icon "$id")
    badges="${badges}[${icon}]"
  done
  echo "$badges"
}

# 전체 업적 대시보드
achievement_dashboard() {
  echo "=== GolemGarden Achievement Dashboard ==="
  echo ""

  if [ ! -f "$ACHIEVEMENT_FILE" ]; then
    echo "  업적 없음. forge log-add로 태스크를 기록하면 자동으로 업적이 추적됩니다."
    return
  fi

  printf "%-10s %-8s %s\n" "SOUL" "Count" "Badges"
  printf "%-10s %-8s %s\n" "----" "-----" "------"

  # SOUL별 그룹화
  grep -o '"soul":"[^"]*"' "$ACHIEVEMENT_FILE" | sort -u | sed 's/"soul":"//;s/"//' | while IFS= read -r soul; do
    local count=$(grep "\"soul\":\"${soul}\"" "$ACHIEVEMENT_FILE" | wc -l | tr -d ' \r')
    local badges=""
    grep "\"soul\":\"${soul}\"" "$ACHIEVEMENT_FILE" | while IFS= read -r line; do
      local id=$(echo "$line" | grep -o '"id":"[^"]*"' | sed 's/"id":"//;s/"//')
      local icon=$(_ach_icon "$id")
      printf "[%s]" "$icon"
    done | { read -r b; printf "%-10s %-8s %s\n" "$soul" "${count}개" "$b"; }
  done
}
