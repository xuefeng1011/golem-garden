#!/usr/bin/env bash
# insights.sh — SOUL 성과 패턴 분석
# growth-log 데이터로 SOUL별 인사이트를 생성한다.
# Hermes Agent의 session insights 패턴을 GolemGarden에 적용.
#
# Usage: source lib/insights.sh && insights_soul ryn
#        source lib/insights.sh && insights_team

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${GOLEM_ROOT}/lib/soul-parser.sh"
source "${GOLEM_ROOT}/lib/growth-log.sh"

# ── SOUL별 인사이트 ──

# insights_soul <soul_name>
# 개별 SOUL의 성과 패턴 분석
insights_soul() {
  local soul_name="$1"
  local soul_file=$(_resolve_soul_file "$soul_name")
  [ ! -f "$soul_file" ] && echo "[insights] SOUL not found: $soul_name" && return 1

  soul_parse "$soul_file"

  # 모든 growth-log 수집 (글로벌 + 프로젝트, 중복 방지)
  local all_entries=""
  local global_log="${GOLEM_ROOT}/growth-log/${soul_name}.jsonl"
  local project_log="${GOLEM_PROJECT:+${GOLEM_PROJECT}/.golem/growth-log/${soul_name}.jsonl}"
  [ -f "$global_log" ] && all_entries="$(cat "$global_log")"$'\n'
  if [ -n "$project_log" ] && [ -f "$project_log" ] && [ "$project_log" != "$global_log" ]; then
    all_entries="${all_entries}$(cat "$project_log")"$'\n'
  fi

  if [ -z "$all_entries" ] || [ "$(echo "$all_entries" | grep -c '.')" -lt 1 ]; then
    echo "[insights] ${soul_name}: 데이터 부족 (최소 1건 필요)"
    return 1
  fi

  local successes=$(echo "$all_entries" | grep -c '"result":"success"' 2>/dev/null)
  local fails=$(echo "$all_entries" | grep -c '"result":"fail"' 2>/dev/null)
  local timeouts=$(echo "$all_entries" | grep -c '"result":"timeout"' 2>/dev/null)
  local turn_caps=$(echo "$all_entries" | grep -c '"result":"turn_cap"' 2>/dev/null)
  # "result":"값" 형태의 라인만 집계 — 구 grep '"result"' 는 값 없는 유령 라인까지
  # 세던 버그. 알려지지 않은 값(예: partial 도입 시)은 사라지지 않고 기타로 노출.
  local with_result=$(echo "$all_entries" | grep -c '"result":"' 2>/dev/null)
  local total=$with_result
  local others=$((with_result - successes - fails - timeouts - turn_caps))
  [ "$others" -lt 0 ] && others=0
  local rate=0
  [ "$total" -gt 0 ] && rate=$(( successes * 100 / total ))

  # 비용 합산
  local total_cost=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local c=$(echo "$line" | sed -n 's/.*"cost_usd":\([0-9.]*\).*/\1/p')
    [ -n "$c" ] && total_cost=$(awk "BEGIN{printf \"%.3f\", ${total_cost} + ${c}}")
  done <<< "$all_entries"

  # 평균 비용
  local avg_cost=0
  [ "$total" -gt 0 ] && avg_cost=$(awk "BEGIN{printf \"%.3f\", ${total_cost} / ${total}}")

  # 최근 성과 추세 (최근 5건 vs 이전)
  local recent_5=""
  local recent_success=0
  recent_5=$(echo "$all_entries" | grep '"result"' | tail -5)
  recent_success=$(echo "$recent_5" | grep -c '"result":"success"' 2>/dev/null)
  local recent_rate=0
  local recent_total=$(echo "$recent_5" | grep -c '"result"' 2>/dev/null)
  [ "$recent_total" -gt 0 ] && recent_rate=$(( recent_success * 100 / recent_total ))

  local trend="→"
  [ "$recent_rate" -gt "$rate" ] && trend="↑"
  [ "$recent_rate" -lt "$rate" ] && trend="↓"

  # 연속 성공 (현재 streak) — tac 없는 환경 대응
  local reversed_entries=""
  if command -v tac >/dev/null 2>&1; then
    reversed_entries=$(echo "$all_entries" | grep '"result"' | tac)
  else
    reversed_entries=$(echo "$all_entries" | grep '"result"' | awk '{lines[NR]=$0} END{for(i=NR;i>=1;i--) print lines[i]}')
  fi
  local streak=$(echo "$reversed_entries" | awk '/"result":"success"/{c++; next}{exit}END{print c+0}')

  # 모델별 비용
  local model_breakdown=""
  for m in opus sonnet haiku; do
    local m_count=$(echo "$all_entries" | grep -c "\"model\":\"${m}\"" 2>/dev/null)
    if [ "$m_count" -gt 0 ]; then
      local m_cost=0
      while IFS= read -r line; do
        local c=$(echo "$line" | sed -n 's/.*"cost_usd":\([0-9.]*\).*/\1/p')
        [ -n "$c" ] && m_cost=$(awk "BEGIN{printf \"%.3f\", ${m_cost} + ${c}}")
      done <<< "$(echo "$all_entries" | grep "\"model\":\"${m}\"")"
      model_breakdown="${model_breakdown}    ${m}: ${m_count}건, \$${m_cost}\n"
    fi
  done

  # 최고 성과 태스크 (가장 많은 파일 변경)
  local best_task=""
  local best_files=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local f=$(echo "$line" | sed -n 's/.*"files_changed":\([0-9]*\).*/\1/p')
    [ -z "$f" ] && continue
    if [ "$f" -gt "$best_files" ] 2>/dev/null; then
      best_files=$f
      best_task=$(echo "$line" | sed -n 's/.*"task":"\([^"]*\)".*/\1/p')
    fi
  done <<< "$all_entries"

  # 출력
  echo "=== ${SOUL_NAME} 인사이트 ==="
  echo ""
  echo "  역할: ${SOUL_ROLE} | 랭크: ${SOUL_RANK} | 모델: ${SOUL_MODEL}"
  echo ""
  echo "── 성과 요약 ──"
  printf "  태스크: %d건 (성공 %d / 실패 %d)\n" "$total" "$successes" "$fails"
  printf "  성공률: %d%% %s (최근5건: %d%%)\n" "$rate" "$trend" "$recent_rate"
  printf "  연속성공: %d건\n" "$streak"
  echo ""
  echo "── 실패 유형 분해 ──"
  local fail_count=$fails
  local timeout_count=$timeouts
  local turn_cap_count=$turn_caps
  local other_count=$others
  local non_success=$((fail_count + timeout_count + turn_cap_count + other_count))
  if [ "$non_success" -gt 0 ]; then
    [ "$fail_count" -gt 0 ] && printf "  실패(fail): %d건 (%.1f%%)\n" "$fail_count" "$(awk "BEGIN{printf \"%.1f\", $fail_count*100/$non_success}")"
    [ "$timeout_count" -gt 0 ] && printf "  타임아웃: %d건 (%.1f%%)\n" "$timeout_count" "$(awk "BEGIN{printf \"%.1f\", $timeout_count*100/$non_success}")"
    [ "$turn_cap_count" -gt 0 ] && printf "  턴캡: %d건 (%.1f%%)\n" "$turn_cap_count" "$(awk "BEGIN{printf \"%.1f\", $turn_cap_count*100/$non_success}")"
    [ "$other_count" -gt 0 ] && printf "  기타: %d건 (%.1f%%)\n" "$other_count" "$(awk "BEGIN{printf \"%.1f\", $other_count*100/$non_success}")"
  else
    echo "  실패 없음 (모두 성공)"
  fi
  echo ""
  echo "── 비용 분석 ──"
  printf "  총비용: \$%s | 평균: \$%s/태스크\n" "$total_cost" "$avg_cost"
  if [ -n "$model_breakdown" ]; then
    echo "  모델별:"
    printf "$model_breakdown"
  fi
  echo ""
  echo "── 주목할 점 ──"
  if [ -n "$best_task" ] && [ "$best_files" -gt 0 ]; then
    printf "  최대 규모 태스크: %s (%d파일)\n" "$best_task" "$best_files"
  fi
  if [ "$recent_rate" -gt "$rate" ] && [ "$total" -ge 5 ]; then
    echo "  추세: 최근 성과가 전체 평균보다 높음 — 성장 중"
  elif [ "$recent_rate" -lt "$rate" ] && [ "$total" -ge 5 ]; then
    echo "  추세: 최근 성과가 전체 평균보다 낮음 — 태스크 난이도 확인 필요"
  fi
  if [ "$streak" -ge 5 ]; then
    echo "  연속성공 ${streak}건 — 높은 안정성"
  fi

  # 학습 메모리 통계
  local mem_file="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/memory/${soul_name}.jsonl"
  if [ -f "$mem_file" ]; then
    local mem_count=$(wc -l < "$mem_file" | tr -d ' \r')
    echo ""
    echo "── 학습 기억 ──"
    printf "  기억 수: %d건\n" "$mem_count"
    # 태그 빈도 상위 3개
    local top_tags=$(grep -o '"tags":"[^"]*"' "$mem_file" 2>/dev/null | sed 's/"tags":"//;s/"//' | tr ',' '\n' | sed 's/^[[:space:]]*//' | sort | uniq -c | sort -rn | head -3)
    if [ -n "$top_tags" ]; then
      echo "  주요 학습 영역:"
      echo "$top_tags" | while read count tag; do
        [ -z "$tag" ] && continue
        printf "    %s (%d건)\n" "$tag" "$count"
      done
    fi
  fi
}

# ── 팀 전체 인사이트 ──

# insights_team
# 팀 전체의 비교 분석
insights_team() {
  echo "=== GolemGarden Team Insights ==="
  echo ""

  # 헤더
  printf "%-10s %-8s %-6s %-8s %-10s %-8s %-12s %s\n" \
    "SOUL" "Tasks" "Rate" "Trend" "Cost" "Avg" "Failures" "Streak"
  printf "%-10s %-8s %-6s %-8s %-10s %-8s %-12s %s\n" \
    "----" "-----" "----" "-----" "----" "---" "--------" "------"

  local team_total=0
  local team_cost=0
  local team_success=0

  while IFS= read -r soul_file; do
    [ -f "$soul_file" ] || continue
    soul_parse "$soul_file"
    [ "$SOUL_ROLE" = "director" ] && continue

    local name="$SOUL_NAME"

    # 데이터 수집
    local all_entries=""
    local gl="${GOLEM_ROOT}/growth-log/${name}.jsonl"
    local pl="${GOLEM_PROJECT:+${GOLEM_PROJECT}/.golem/growth-log/${name}.jsonl}"
    [ -f "$gl" ] && all_entries="$(cat "$gl")"$'\n'
    if [ -n "$pl" ] && [ -f "$pl" ] && [ "$pl" != "$gl" ]; then
      all_entries="${all_entries}$(cat "$pl")"$'\n'
    fi

    local successes=$(echo "$all_entries" | grep -c '"result":"success"' 2>/dev/null)
    local fails=$(echo "$all_entries" | grep -c '"result":"fail"' 2>/dev/null)
    local timeouts=$(echo "$all_entries" | grep -c '"result":"timeout"' 2>/dev/null)
    local turn_caps=$(echo "$all_entries" | grep -c '"result":"turn_cap"' 2>/dev/null)
    # soul 뷰와 동일 규칙: "result":"값" 라인만 총계 (미지 값도 총계에 포함)
    local total=$(echo "$all_entries" | grep -c '"result":"' 2>/dev/null)
    [ "$total" -eq 0 ] && continue

    local rate=$(( successes * 100 / total ))

    # 비용
    local cost=0
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      local c=$(echo "$line" | sed -n 's/.*"cost_usd":\([0-9.]*\).*/\1/p')
      [ -n "$c" ] && cost=$(awk "BEGIN{printf \"%.3f\", ${cost} + ${c}}")
    done <<< "$all_entries"
    local avg=0
    [ "$total" -gt 0 ] && avg=$(awk "BEGIN{printf \"%.3f\", ${cost} / ${total}}")

    # 추세
    local recent_success=$(echo "$all_entries" | grep '"result"' | tail -5 | grep -c '"result":"success"' 2>/dev/null)
    local recent_total=$(echo "$all_entries" | grep '"result"' | tail -5 | grep -c '"result"' 2>/dev/null)
    local recent_rate=0
    [ "$recent_total" -gt 0 ] && recent_rate=$(( recent_success * 100 / recent_total ))
    local trend="→"
    [ "$recent_rate" -gt "$rate" ] && trend="↑"
    [ "$recent_rate" -lt "$rate" ] && trend="↓"

    # streak (tac 폴백)
    local rev_entries=""
    if command -v tac >/dev/null 2>&1; then
      rev_entries=$(echo "$all_entries" | grep '"result"' | tac)
    else
      rev_entries=$(echo "$all_entries" | grep '"result"' | awk '{lines[NR]=$0} END{for(i=NR;i>=1;i--) print lines[i]}')
    fi
    local streak=$(echo "$rev_entries" | awk '/"result":"success"/{c++; next}{exit}END{print c+0}')

    local failures=""
    if [ "$fails" -gt 0 ] || [ "$timeouts" -gt 0 ] || [ "$turn_caps" -gt 0 ]; then
      failures="${fails}f·${timeouts}t·${turn_caps}c"
    else
      failures="—"
    fi

    printf "%-10s %-8s %-6s %-8s %-10s %-8s %-12s %s\n" \
      "$name" "${total}건" "${rate}%" "$trend" "\$${cost}" "\$${avg}" "$failures" "${streak}연속"

    team_total=$((team_total + total))
    team_success=$((team_success + successes))
    team_cost=$(awk "BEGIN{printf \"%.3f\", ${team_cost} + ${cost}}")
  done < <(_all_soul_files)

  echo ""
  local team_rate=0
  [ "$team_total" -gt 0 ] && team_rate=$(( team_success * 100 / team_total ))
  printf "  합계: %d건, 성공률 %d%%, 총비용 \$%s\n" "$team_total" "$team_rate" "$team_cost"

  # ── 팀 전체 실패 분석 ──
  echo ""
  echo "── 실패 유형 분석 ──"
  local team_fails=0
  local team_timeouts=0
  local team_turn_caps=0
  local team_others=0
  while IFS= read -r soul_file; do
    [ -f "$soul_file" ] || continue
    soul_parse "$soul_file"
    [ "$SOUL_ROLE" = "director" ] && continue
    local name="$SOUL_NAME"

    local all_entries=""
    local gl="${GOLEM_ROOT}/growth-log/${name}.jsonl"
    local pl="${GOLEM_PROJECT:+${GOLEM_PROJECT}/.golem/growth-log/${name}.jsonl}"
    [ -f "$gl" ] && all_entries="$(cat "$gl")"$'\n'
    if [ -n "$pl" ] && [ -f "$pl" ] && [ "$pl" != "$gl" ]; then
      all_entries="${all_entries}$(cat "$pl")"$'\n'
    fi

    local total=$(echo "$all_entries" | grep -c '"result"' 2>/dev/null)
    [ "$total" -eq 0 ] && continue

    local fails=$(echo "$all_entries" | grep -c '"result":"fail"' 2>/dev/null)
    local timeouts=$(echo "$all_entries" | grep -c '"result":"timeout"' 2>/dev/null)
    local turn_caps=$(echo "$all_entries" | grep -c '"result":"turn_cap"' 2>/dev/null)
    local successes=$(echo "$all_entries" | grep -c '"result":"success"' 2>/dev/null)
    local others=$((total - successes - fails - timeouts - turn_caps))

    local non_success=$((fails + timeouts + turn_caps + others))
    [ "$non_success" -gt 0 ] && printf "  %-10s: " "$name" && {
      local parts=""
      [ "$fails" -gt 0 ] && parts="${parts}fail=$fails "
      [ "$timeouts" -gt 0 ] && parts="${parts}timeout=$timeouts "
      [ "$turn_caps" -gt 0 ] && parts="${parts}turn_cap=$turn_caps "
      [ "$others" -gt 0 ] && parts="${parts}기타=$others"
      echo "$parts" | sed 's/[[:space:]]*$//'
    }

    team_fails=$((team_fails + fails))
    team_timeouts=$((team_timeouts + timeouts))
    team_turn_caps=$((team_turn_caps + turn_caps))
    team_others=$((team_others + others))
  done < <(_all_soul_files)

  local team_non_success=$((team_fails + team_timeouts + team_turn_caps + team_others))
  echo ""
  printf "  팀 합계: "
  [ "$team_fails" -gt 0 ] && printf "fail=%d " "$team_fails"
  [ "$team_timeouts" -gt 0 ] && printf "timeout=%d " "$team_timeouts"
  [ "$team_turn_caps" -gt 0 ] && printf "turn_cap=%d " "$team_turn_caps"
  [ "$team_others" -gt 0 ] && printf "기타=%d" "$team_others"
  echo ""

  # MVP (가장 많은 태스크 성공)
  echo ""
  echo "── 팀 하이라이트 ──"

  local mvp="" mvp_tasks=0
  local efficient="" efficient_cost=999
  while IFS= read -r soul_file; do
    [ -f "$soul_file" ] || continue
    soul_parse "$soul_file"
    [ "$SOUL_ROLE" = "director" ] && continue
    local name="$SOUL_NAME"

    local all_entries=""
    local gl="${GOLEM_ROOT}/growth-log/${name}.jsonl"
    local pl="${GOLEM_PROJECT:+${GOLEM_PROJECT}/.golem/growth-log/${name}.jsonl}"
    [ -f "$gl" ] && all_entries="$(cat "$gl")"$'\n'
    if [ -n "$pl" ] && [ -f "$pl" ] && [ "$pl" != "$gl" ]; then
      all_entries="${all_entries}$(cat "$pl")"$'\n'
    fi

    local successes=$(echo "$all_entries" | grep -c '"result":"success"' 2>/dev/null)
    if [ "$successes" -gt "$mvp_tasks" ]; then
      mvp_tasks=$successes
      mvp="$name"
    fi

    local total=$(echo "$all_entries" | grep -c '"result"' 2>/dev/null)
    if [ "$total" -ge 3 ]; then
      local cost=0
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        local c=$(echo "$line" | sed -n 's/.*"cost_usd":\([0-9.]*\).*/\1/p')
        [ -n "$c" ] && cost=$(awk "BEGIN{printf \"%.3f\", ${cost} + ${c}}")
      done <<< "$all_entries"
      local avg_c=$(awk "BEGIN{v=${cost}/${total}; printf \"%.3f\", v}")
      if awk "BEGIN{exit !(${avg_c} < ${efficient_cost} && ${avg_c} > 0)}"; then
        efficient_cost="$avg_c"
        efficient="$name"
      fi
    fi
  done < <(_all_soul_files)

  [ -n "$mvp" ] && echo "  MVP: ${mvp} (${mvp_tasks}건 성공)"
  [ -n "$efficient" ] && echo "  비용 효율 최고: ${efficient} (평균 \$${efficient_cost}/태스크)"
}

# ── forge insights 진입점 ──

insights_main() {
  local target="${1:-team}"

  case "$target" in
    team|"")
      insights_team
      ;;
    *)
      insights_soul "$target"
      ;;
  esac
}
