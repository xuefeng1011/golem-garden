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

_json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' -e 's/\r/\\r/g' | awk '{if(NR>1) printf "\\n"; printf "%s",$0}'
}

# SOUL 이름 검증 — 경로 순회 및 명령 주입 방지
# 허용: 영문 소대문자, 숫자, 하이픈, 언더스코어
_validate_soul_name() {
  local name="$1"
  if [ -z "$name" ] || [ "$name" = "." ] || [ "$name" = ".." ]; then
    echo "[ERROR] 잘못된 SOUL 이름: '${name}'" >&2
    return 1
  fi
  if echo "$name" | grep -q '[^a-zA-Z0-9_-]'; then
    echo "[ERROR] SOUL 이름에 허용되지 않는 문자: '${name}'" >&2
    return 1
  fi
  return 0
}

# SOUL 파일 검색: .golem/souls/ 우선 → 글로벌 souls/ 폴백
_resolve_soul_file() {
  local name="$1"
  name=$(basename "$name" .md)
  name=$(basename "$name")

  # 경로 순회 검증
  _validate_soul_name "$name" || return 1

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

  # Phase 1 확장 필드 (없으면 rank 기반 기본값 사용)
  SOUL_TOOLS=$(soul_get_field "$soul_file" "tools" | tr -d '[]')
  SOUL_MAX_TURNS=$(soul_get_field "$soul_file" "maxTurns")
  SOUL_ISOLATION=$(soul_get_field "$soul_file" "isolation")
  SOUL_EFFORT=$(soul_get_field "$soul_file" "effort")

  # 기본값 적용 (하위 호환)
  if [ -z "$SOUL_TOOLS" ]; then
    case "$SOUL_RANK" in
      novice)      SOUL_TOOLS="Read, Edit, Grep, Glob" ;;
      junior)      SOUL_TOOLS="Read, Edit, Write, Bash, Grep, Glob" ;;
      senior)      SOUL_TOOLS="Read, Edit, Write, Bash, Grep, Glob, Agent, WebFetch" ;;
      lead)        SOUL_TOOLS="Read, Edit, Write, Bash, Grep, Glob, Agent, WebFetch, SendMessage" ;;
      master)      SOUL_TOOLS="Read, Edit, Write, Bash, Grep, Glob, Agent, WebFetch, SendMessage, TaskCreate" ;;
    esac
    [ "$SOUL_ROLE" = "director" ] && SOUL_TOOLS="Agent, SendMessage, TaskCreate, TaskStop, Read, Grep, Glob"
  fi

  # Coordinator 도구 분리 (시스템 레벨 강제)
  # Director는 실행 도구(Edit, Write, Bash)를 절대 보유할 수 없음
  # 프롬프트가 아닌 도구 필터링으로 강제
  if [ "$SOUL_ROLE" = "director" ]; then
    SOUL_TOOLS="Agent, SendMessage, TaskCreate, TaskStop, Read, Grep, Glob"
    SOUL_DISALLOWED_TOOLS="Edit, Write, Bash, FileEdit, FileWrite, NotebookEdit"
    SOUL_IS_COORDINATOR="true"
  else
    SOUL_DISALLOWED_TOOLS=""
    SOUL_IS_COORDINATOR="false"
  fi
  if [ -z "$SOUL_MAX_TURNS" ]; then
    case "$SOUL_RANK" in
      novice) SOUL_MAX_TURNS=15 ;; junior) SOUL_MAX_TURNS=25 ;; senior) SOUL_MAX_TURNS=40 ;;
      lead)   SOUL_MAX_TURNS=60 ;; master) SOUL_MAX_TURNS=80 ;;
    esac
    [ "$SOUL_ROLE" = "director" ] && SOUL_MAX_TURNS=50
  fi
  [ -z "$SOUL_ISOLATION" ] && {
    case "$SOUL_RANK" in
      novice|junior) SOUL_ISOLATION="none" ;;
      *) SOUL_ISOLATION="worktree" ;;
    esac
    [ "$SOUL_ROLE" = "director" ] && SOUL_ISOLATION="none"
    [ "$SOUL_ROLE" = "qa-tester" ] && SOUL_ISOLATION="none"
  }
  [ -z "$SOUL_EFFORT" ] && {
    case "$SOUL_MODEL" in
      haiku) SOUL_EFFORT="low" ;; sonnet) SOUL_EFFORT="medium" ;; opus) SOUL_EFFORT="high" ;; *) SOUL_EFFORT="medium" ;;
    esac
  }

  # personality는 프롬프트에 주입하지 않음 (사용자 메모용)
  SOUL_PERSONALITY=$(soul_get_field "$soul_file" "personality")
}

# ── 글로벌 변수 오염 방지 래퍼 ──
# soul_parse는 전역 SOUL_NAME 등을 덮어씀.
# 루프에서 반복 호출 시 이전 값이 손실되는 문제를 방지하려면:
#
# 방법 1: soul_save/soul_restore — 현재 상태를 스택에 저장/복원
# 방법 2: soul_get — 특정 필드만 읽기 (파싱 없이)
#
# 사용 예시:
#   soul_save
#   soul_parse "$other_file"   # 전역 변수 덮어써짐
#   local other_name="$SOUL_NAME"
#   soul_restore                # 원래 값 복원

# 구분자: ASCII 0x01 (SOH) — 필드 값에 절대 나타나지 않는 non-printing 문자
_SOUL_SEP=$'\x01'
_SOUL_SAVED_STATE=""

soul_save() {
  # 현재 전역 변수를 저장 (단일 레벨 — 이중 save 시 경고)
  if [ -n "$_SOUL_SAVED_STATE" ]; then
    echo "[WARN] soul_save: 이전 저장이 복원되지 않았음 — 덮어씁니다" >&2
  fi
  _SOUL_SAVED_STATE="${SOUL_NAME}${_SOUL_SEP}${SOUL_ROLE}${_SOUL_SEP}${SOUL_RANK}${_SOUL_SEP}${SOUL_MODEL}${_SOUL_SEP}${SOUL_TOOLS}${_SOUL_SEP}${SOUL_MAX_TURNS}${_SOUL_SEP}${SOUL_ISOLATION}${_SOUL_SEP}${SOUL_EFFORT}${_SOUL_SEP}${SOUL_SPECIALTY}${_SOUL_SEP}${SOUL_CREATED}${_SOUL_SEP}${SOUL_PERSONALITY}${_SOUL_SEP}${SOUL_DISALLOWED_TOOLS}${_SOUL_SEP}${SOUL_IS_COORDINATOR}"
}

soul_restore() {
  # 저장된 상태에서 전역 변수 복원
  if [ -z "$_SOUL_SAVED_STATE" ]; then
    echo "[WARN] soul_restore: 저장된 상태 없음" >&2
    return 1
  fi
  IFS="$_SOUL_SEP" read -r SOUL_NAME SOUL_ROLE SOUL_RANK SOUL_MODEL SOUL_TOOLS SOUL_MAX_TURNS SOUL_ISOLATION SOUL_EFFORT SOUL_SPECIALTY SOUL_CREATED SOUL_PERSONALITY SOUL_DISALLOWED_TOOLS SOUL_IS_COORDINATOR <<< "$_SOUL_SAVED_STATE"
  _SOUL_SAVED_STATE=""
}

# 단일 필드 조회 (soul_parse 없이, 전역 변수 오염 없음)
# soul_get <soul_name_or_file> <field>
# 예: local name=$(soul_get ryn name)
soul_get() {
  local target="$1"
  local field="$2"

  local soul_file="$target"
  if [ ! -f "$soul_file" ]; then
    soul_file=$(_resolve_soul_file "$target")
  fi
  [ -z "$soul_file" ] || [ ! -f "$soul_file" ] && return 1

  soul_get_field "$soul_file" "$field"
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
  printf "%-10s %-22s %-10s %-8s %-10s %-6s %s\n" "Name" "Role" "Rank" "Model" "Isolation" "Turns" "Specialty"
  printf "%-10s %-22s %-10s %-8s %-10s %-6s %s\n" "----" "----" "----" "-----" "---------" "-----" "---------"

  while IFS= read -r soul_file; do
    [ -f "$soul_file" ] || continue
    soul_parse "$soul_file"
    printf "%-10s %-22s %-10s %-8s %-10s %-6s %s\n" "$SOUL_NAME" "$SOUL_ROLE" "$SOUL_RANK" "$SOUL_MODEL" "$SOUL_ISOLATION" "$SOUL_MAX_TURNS" "$SOUL_SPECIALTY"
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
