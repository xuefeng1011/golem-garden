#!/bin/bash
# chemistry.sh — SOUL Chemistry (팀 케미 추적)
# SOUL 쌍별 협업 성과를 데이터로 추적하여 최적 팀 구성 근거 제공
# Usage: source lib/chemistry.sh && chemistry_record ryn zen pass 0

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${GOLEM_ROOT}/lib/soul-parser.sh"

# 케미 데이터 파일
CHEMISTRY_FILE="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/chemistry.jsonl"

# 케미 기록 (두 SOUL의 협업 결과)
# chemistry_record <soul1> <soul2> <interaction_type> <result> [detail]
# interaction_type: review | collab | dependency | conflict
# result: positive | negative | neutral
chemistry_record() {
  local soul1="$1"
  local soul2="$2"
  local interaction="$3"
  local result="$4"
  local detail="${5:-}"

  mkdir -p "$(dirname "$CHEMISTRY_FILE")"

  local date=$(date +%Y-%m-%d)
  # 항상 알파벳 순으로 정렬 (a-b = b-a 동일 쌍)
  local pair
  if [[ "$soul1" < "$soul2" ]]; then
    pair="${soul1}:${soul2}"
  else
    pair="${soul2}:${soul1}"
  fi

  detail=$(_json_escape "$detail")
  echo "{\"date\":\"${date}\",\"pair\":\"${pair}\",\"type\":\"${interaction}\",\"result\":\"${result}\",\"detail\":\"${detail}\"}" >> "$CHEMISTRY_FILE"
  echo "[chemistry] ${pair}: ${interaction} → ${result}"
}

# 케미 점수 계산 (0~100)
# chemistry_score <soul1> <soul2>
chemistry_score() {
  local soul1="$1"
  local soul2="$2"

  if [ ! -f "$CHEMISTRY_FILE" ]; then
    echo "50"  # 기본 중립
    return
  fi

  local pair
  if [[ "$soul1" < "$soul2" ]]; then
    pair="${soul1}:${soul2}"
  else
    pair="${soul2}:${soul1}"
  fi

  local total=$(grep "\"pair\":\"${pair}\"" "$CHEMISTRY_FILE" 2>/dev/null | wc -l | tr -d ' \r')
  total=${total:-0}

  if [ "$total" -eq 0 ]; then
    echo "50"  # 기록 없으면 중립
    return
  fi

  local positive=$(grep "\"pair\":\"${pair}\"" "$CHEMISTRY_FILE" 2>/dev/null | grep -c '"result":"positive"' | tr -d ' \r')
  local negative=$(grep "\"pair\":\"${pair}\"" "$CHEMISTRY_FILE" 2>/dev/null | grep -c '"result":"negative"' | tr -d ' \r')
  positive=${positive:-0}
  negative=${negative:-0}

  # 점수 = 50 + (positive - negative) * 50 / total, 0~100 범위
  local raw_score=$(( 50 + (positive - negative) * 50 / total ))

  # 클램핑
  [ "$raw_score" -lt 0 ] && raw_score=0
  [ "$raw_score" -gt 100 ] && raw_score=100

  echo "$raw_score"
}

# 케미 등급 변환
_chemistry_grade() {
  local score="$1"
  if [ "$score" -ge 90 ]; then
    echo "S"
  elif [ "$score" -ge 75 ]; then
    echo "A"
  elif [ "$score" -ge 60 ]; then
    echo "B"
  elif [ "$score" -ge 40 ]; then
    echo "C"
  elif [ "$score" -ge 20 ]; then
    echo "D"
  else
    echo "F"
  fi
}

# 특정 SOUL의 최고 케미 파트너 찾기
# chemistry_best_partner <soul_name>
chemistry_best_partner() {
  local soul_name="$1"
  local best_partner=""
  local best_score=0

  while IFS= read -r soul_file; do
    [ -f "$soul_file" ] || continue
    soul_parse "$soul_file"
    [ "$SOUL_NAME" = "$soul_name" ] && continue

    local score=$(chemistry_score "$soul_name" "$SOUL_NAME")
    if [ "$score" -gt "$best_score" ]; then
      best_score=$score
      best_partner="$SOUL_NAME"
    fi
  done < <(_all_soul_files)

  if [ -n "$best_partner" ]; then
    echo "${best_partner}:${best_score}"
  fi
}

# Coordinator용: 케미 정보를 포함한 팀 구성 추천
# chemistry_team_recommend <souls_csv>
chemistry_team_recommend() {
  local souls_csv="$1"
  local souls=$(echo "$souls_csv" | tr ',' ' ' | tr -d ' ')

  echo "=== 팀 케미 매트릭스 ==="
  echo ""

  # 헤더
  printf "%-10s" ""
  for s2 in $souls; do
    printf "%-10s" "$s2"
  done
  echo ""

  # 행
  for s1 in $souls; do
    printf "%-10s" "$s1"
    for s2 in $souls; do
      if [ "$s1" = "$s2" ]; then
        printf "%-10s" "—"
      else
        local score=$(chemistry_score "$s1" "$s2")
        local grade=$(_chemistry_grade "$score")
        printf "%-10s" "${score}(${grade})"
      fi
    done
    echo ""
  done
}

# 케미 대시보드
chemistry_dashboard() {
  echo "=== GolemGarden Chemistry Dashboard ==="
  echo ""

  if [ ! -f "$CHEMISTRY_FILE" ]; then
    echo "  케미 데이터 없음. 리뷰/협업 후 자동으로 누적됩니다."
    return
  fi

  local total=$(wc -l < "$CHEMISTRY_FILE" | tr -d ' \r')
  echo "  총 상호작용: ${total}건"
  echo ""

  # 모든 쌍별 점수
  printf "%-15s %-8s %-6s %-10s %s\n" "Pair" "Score" "Grade" "Records" "Detail"
  printf "%-15s %-8s %-6s %-10s %s\n" "----" "-----" "-----" "-------" "------"

  # 유니크 쌍 추출
  grep -o '"pair":"[^"]*"' "$CHEMISTRY_FILE" | sort -u | sed 's/"pair":"//;s/"//' | while IFS= read -r pair; do
    [ -z "$pair" ] && continue
    local s1=$(echo "$pair" | cut -d: -f1)
    local s2=$(echo "$pair" | cut -d: -f2)
    local score=$(chemistry_score "$s1" "$s2")
    local grade=$(_chemistry_grade "$score")
    local records=$(grep "\"pair\":\"${pair}\"" "$CHEMISTRY_FILE" | wc -l | tr -d ' \r')
    local last_detail=$(grep "\"pair\":\"${pair}\"" "$CHEMISTRY_FILE" | tail -1 | grep -o '"detail":"[^"]*"' | sed 's/"detail":"//;s/"//' | cut -c1-25)

    printf "%-15s %-8s %-6s %-10s %s\n" "$pair" "$score" "$grade" "${records}건" "$last_detail"
  done
}
