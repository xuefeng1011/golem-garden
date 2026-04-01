#!/bin/bash
# forge-review.sh — 크로스 리뷰 실행 로직
# Usage: source lib/forge-review.sh && review_execute ryn zen "AuthController"

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${GOLEM_ROOT}/lib/soul-parser.sh"
source "${GOLEM_ROOT}/lib/growth-log.sh"
source "${GOLEM_ROOT}/lib/rank-system.sh"
source "${GOLEM_ROOT}/lib/prompt-builder.sh"

# 리뷰어 자동 선정 (작업자와 다른 SOUL 중 최적)
review_select_reviewer() {
  local worker_name="$1"
  local worker_file=$(_resolve_soul_file "$worker_name")

  soul_parse "$worker_file"
  local worker_role="$SOUL_ROLE"

  # QA SOUL이 있으면 우선 배정
  while IFS= read -r soul_file; do
    [ -f "$soul_file" ] || continue
    soul_parse "$soul_file"
    [ "$SOUL_NAME" = "$worker_name" ] && continue
    if [ "$SOUL_ROLE" = "qa-tester" ]; then
      echo "$SOUL_NAME"
      return 0
    fi
  done < <(_all_soul_files)

  # QA가 없으면 Director 배정
  while IFS= read -r soul_file; do
    [ -f "$soul_file" ] || continue
    soul_parse "$soul_file"
    [ "$SOUL_NAME" = "$worker_name" ] && continue
    if [ "$SOUL_ROLE" = "director" ]; then
      echo "$SOUL_NAME"
      return 0
    fi
  done < <(_all_soul_files)

  # 그 외 아무 다른 SOUL
  while IFS= read -r soul_file; do
    [ -f "$soul_file" ] || continue
    soul_parse "$soul_file"
    [ "$SOUL_NAME" = "$worker_name" ] && continue
    echo "$SOUL_NAME"
    return 0
  done < <(_all_soul_files)

  echo ""
  return 1
}

# 리뷰 필요 여부 판단 (rank 기반)
review_is_required() {
  local soul_name="$1"
  local soul_file=$(_resolve_soul_file "$soul_name")

  soul_parse "$soul_file"

  case "$SOUL_RANK" in
    novice|junior)
      echo "required"
      ;;
    senior)
      echo "optional"
      ;;
    lead|master)
      echo "exempt"
      ;;
    *)
      echo "required"
      ;;
  esac
}

# 리뷰 실행 (프롬프트 생성 + 결과 기록)
review_execute() {
  local worker_name="$1"
  local reviewer_name="${2:-}"
  local target="${3:-전체 변경사항}"

  # 리뷰어 미지정 시 자동 선정
  if [ -z "$reviewer_name" ]; then
    reviewer_name=$(review_select_reviewer "$worker_name")
    if [ -z "$reviewer_name" ]; then
      echo "[review] ERROR: 리뷰어를 찾을 수 없습니다. SOUL이 1개뿐입니다."
      return 1
    fi
    echo "[review] 리뷰어 자동 선정: ${reviewer_name}"
  fi

  local worker_file=$(_resolve_soul_file "$worker_name")
  local reviewer_file=$(_resolve_soul_file "$reviewer_name")

  if [ ! -f "$worker_file" ]; then
    echo "[review] ERROR: 작업자 SOUL 없음: ${worker_name}"
    return 1
  fi
  if [ ! -f "$reviewer_file" ]; then
    echo "[review] ERROR: 리뷰어 SOUL 없음: ${reviewer_name}"
    return 1
  fi

  # 리뷰 필요 여부 확인
  local review_req=$(review_is_required "$worker_name")
  echo "[review] ${worker_name} rank 기반 리뷰 정책: ${review_req}"

  # 리뷰 프롬프트 생성
  local review_prompt
  review_prompt=$(prompt_build_review "$reviewer_name" "$worker_name" "$target")

  # OMC 에이전트 정보
  soul_parse "$reviewer_file"
  local omc_agent=$(soul_to_omc_agent "$SOUL_ROLE")

  echo ""
  echo "=== OMC 리뷰 실행 ==="
  echo "  리뷰어: ${reviewer_name} (${SOUL_ROLE})"
  echo "  OMC Agent: ${omc_agent}"
  echo "  모델: ${SOUL_MODEL}"
  echo "  대상: ${target}"
  echo ""

  # 프롬프트를 표준 출력으로 전달 (OMC/Claude Code에서 파이프로 활용)
  echo "--- REVIEW_PROMPT_START ---"
  echo "$review_prompt"
  echo "--- REVIEW_PROMPT_END ---"
  echo ""
  echo "[review] 프롬프트 생성 완료. OMC 에이전트(${omc_agent}, model=${SOUL_MODEL})에 전달하세요."
  echo "[review] 실행 예시: claude --agent ${omc_agent} --model ${SOUL_MODEL} --prompt '<위 프롬프트>'"

  return 0
}

# 리뷰 결과 기록 (리뷰 완료 후 호출)
review_record() {
  local worker_name="$1"
  local reviewer_name="$2"
  local target="$3"
  local result="$4"           # pass | fail
  local issues_found="${5:-0}"
  local severity="${6:-none}"  # none | minor | major | critical

  # 작업자 growth-log
  growth_log_append "$worker_name" "${target} 리뷰" "$result" 0 0 "$reviewer_name" "$result"

  # 리뷰어 growth-log
  local reviewer_log="${GROWTH_DIR}/${reviewer_name}.jsonl"
  local date=$(date +%Y-%m-%d)
  echo "{\"date\":\"${date}\",\"task\":\"${target} 리뷰 (reviewer)\",\"result\":\"success\",\"issues_found\":${issues_found},\"severity\":\"${severity}\"}" >> "$reviewer_log"
  echo "[review] 리뷰 결과 기록 완료: ${worker_name}←${reviewer_name}, ${result} (이슈 ${issues_found}건)"

  # 랭크 승급 체크
  echo ""
  rank_check "$worker_name"
}

# 자동 리뷰 트리거 (forge-team 완료 후 호출)
review_auto_trigger() {
  local worker_name="$1"
  local task="$2"

  local review_req=$(review_is_required "$worker_name")

  if [ "$review_req" = "required" ]; then
    echo "[review] ${worker_name}은(는) ${review_req} 등급 — 자동 리뷰 트리거"
    local reviewer=$(review_select_reviewer "$worker_name")
    if [ -n "$reviewer" ]; then
      review_execute "$worker_name" "$reviewer" "$task"
      return 0
    else
      echo "[review] WARN: 리뷰어 없음, 리뷰 건너뜀"
      return 1
    fi
  elif [ "$review_req" = "optional" ]; then
    echo "[review] ${worker_name}은(는) senior — 리뷰 선택적 (건너뜀)"
    return 0
  else
    echo "[review] ${worker_name}은(는) ${review_req} — 리뷰 면제"
    return 0
  fi
}

# 리뷰 상태 요약
review_status() {
  echo "=== GolemGarden Review Status ==="
  echo ""
  printf "%-10s %-10s %-12s %-10s %s\n" "SOUL" "Rank" "Review" "Reviews" "Last Review"
  printf "%-10s %-10s %-12s %-10s %s\n" "----" "----" "------" "-------" "-----------"

  while IFS= read -r soul_file; do
    [ -f "$soul_file" ] || continue
    soul_parse "$soul_file"
    local name="$SOUL_NAME"
    local rank="$SOUL_RANK"
    local review_req=$(review_is_required "$name")
    local log_file="${GROWTH_DIR}/${name}.jsonl"

    local review_count=0
    local last_review="—"
    if [ -f "$log_file" ]; then
      review_count=$(grep -c '"reviewer"' "$log_file" 2>/dev/null | tr -d '\r' || echo "0")
      last_review=$(grep '"reviewer"' "$log_file" 2>/dev/null | tail -1 | grep -o '"date":"[^"]*"' | sed 's/"date":"//;s/"//' || echo "—")
      [ -z "$last_review" ] && last_review="—"
    fi

    printf "%-10s %-10s %-12s %-10s %s\n" "$name" "$rank" "$review_req" "${review_count}건" "$last_review"
  done < <(_all_soul_files)
}
