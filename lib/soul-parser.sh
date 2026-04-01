#!/bin/bash
# soul-parser.sh — SOUL.md 파일에서 메타데이터 추출
# Usage: source lib/soul-parser.sh && soul_parse souls/ryn.md

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 프로젝트별 .golem/ 경로 (forge.sh에서 설정, 없으면 GOLEM_ROOT 폴백)
GOLEM_DIR="${GOLEM_DIR:-${GOLEM_ROOT}}"
GOLEM_PROJECT="${GOLEM_PROJECT:-${GOLEM_ROOT}}"

# 플랫폼 호환 sed -i 래퍼 (GNU/BSD 대응)
_sed_i() {
  if sed --version 2>/dev/null | grep -q 'GNU'; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

# SOUL 파일 검색: .golem/souls/ 우선 → 글로벌 souls/ 폴백
_resolve_soul_file() {
  local name="$1"
  local project_soul="${GOLEM_DIR}/souls/${name}.md"
  local global_soul="${GOLEM_ROOT}/souls/${name}.md"

  if [ -f "$project_soul" ]; then
    echo "$project_soul"
  elif [ -f "$global_soul" ]; then
    echo "$global_soul"
  else
    echo ""
  fi
}

# 모든 SOUL 파일 경로 반환 (프로젝트 오버라이드 우선, 중복 제거)
_all_soul_files() {
  local seen=""
  # 프로젝트 souls 먼저
  if [ -d "${GOLEM_DIR}/souls" ]; then
    for f in "${GOLEM_DIR}/souls/"*.md; do
      [ -f "$f" ] || continue
      local name=$(basename "$f" .md)
      echo "$f"
      seen="${seen} ${name}"
    done
  fi
  # 글로벌 souls (프로젝트에 없는 것만)
  if [ -d "${GOLEM_ROOT}/souls" ]; then
    for f in "${GOLEM_ROOT}/souls/"*.md; do
      [ -f "$f" ] || continue
      local name=$(basename "$f" .md)
      echo "$seen" | grep -qw "$name" && continue
      echo "$f"
    done
  fi
}

# SOUL.md frontmatter에서 특정 필드 값 추출
soul_get_field() {
  local soul_file="$1"
  local field="$2"
  sed -n '/^---$/,/^---$/p' "$soul_file" | grep "^${field}:" | sed "s/^${field}:[[:space:]]*//"
}

# SOUL.md 전체 메타데이터를 환경변수로 로드
soul_parse() {
  local soul_file="$1"
  if [ ! -f "$soul_file" ]; then
    echo "[ERROR] SOUL 파일 없음: $soul_file" >&2
    return 1
  fi

  SOUL_NAME=$(soul_get_field "$soul_file" "name")
  SOUL_ROLE=$(soul_get_field "$soul_file" "role")
  SOUL_RANK=$(soul_get_field "$soul_file" "rank")
  SOUL_SPECIALTY=$(soul_get_field "$soul_file" "specialty" | tr -d '[]')
  SOUL_MODEL=$(soul_get_field "$soul_file" "model")
  SOUL_CREATED=$(soul_get_field "$soul_file" "created")

  # personality는 프롬프트에 주입하지 않음 (사용자 메모용)
  SOUL_PERSONALITY=$(soul_get_field "$soul_file" "personality")
}

# SOUL role → OMC agent 매핑
soul_to_omc_agent() {
  local role="$1"
  case "$role" in
    director)              echo "architect" ;;
    backend-developer)     echo "executor" ;;
    frontend-developer)    echo "designer" ;;
    qa-tester)             echo "test-engineer" ;;
    devops-engineer)       echo "executor" ;;
    data-analyst)          echo "scientist" ;;
    technical-writer)      echo "writer" ;;
    security-auditor)      echo "security-reviewer" ;;
    game-logic-developer)  echo "executor" ;;
    game-designer)         echo "planner" ;;
    *)                     echo "executor" ;;
  esac
}

# 사용 가능한 SOUL 목록 출력
soul_list() {
  echo "=== GolemGarden SOULs ==="
  echo ""
  printf "%-10s %-22s %-10s %-8s %s\n" "Name" "Role" "Rank" "Model" "Specialty"
  printf "%-10s %-22s %-10s %-8s %s\n" "----" "----" "----" "-----" "---------"

  while IFS= read -r soul_file; do
    [ -f "$soul_file" ] || continue
    soul_parse "$soul_file"
    printf "%-10s %-22s %-10s %-8s %s\n" "$SOUL_NAME" "$SOUL_ROLE" "$SOUL_RANK" "$SOUL_MODEL" "$SOUL_SPECIALTY"
  done < <(_all_soul_files)
}

# SOUL specialty와 태스크 키워드 매칭 점수 계산
soul_match_score() {
  local soul_file="$1"
  local task_keywords="$2"
  local score=0

  soul_parse "$soul_file"
  local specialties=$(echo "$SOUL_SPECIALTY" | tr ',' ' ' | tr -d ' ')

  for keyword in $task_keywords; do
    keyword_lower=$(echo "$keyword" | tr '[:upper:]' '[:lower:]')
    if echo "$SOUL_SPECIALTY" | tr '[:upper:]' '[:lower:]' | grep -q "$keyword_lower"; then
      score=$((score + 10))
    fi
  done

  echo "$score"
}

# 태스크에 최적의 SOUL 찾기 (Director 제외)
soul_find_best_match() {
  local task_keywords="$1"
  local best_soul=""
  local best_score=0

  while IFS= read -r soul_file; do
    [ -f "$soul_file" ] || continue
    soul_parse "$soul_file"

    # Director는 분배자이므로 제외
    [ "$SOUL_ROLE" = "director" ] && continue

    local score=$(soul_match_score "$soul_file" "$task_keywords")
    if [ "$score" -gt "$best_score" ]; then
      best_score=$score
      best_soul="$SOUL_NAME"
    fi
  done < <(_all_soul_files)

  echo "$best_soul"
}
