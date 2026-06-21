#!/usr/bin/env bash
# tool-character.sh — 도구 성격 메타데이터 시스템
# Claude Code의 Tool Character 패턴: isReadOnly, isConcurrencySafe, isDestructive, isIdempotent
# Coordinator가 병렬 실행 안전성을 자동 판단하는 데 사용
# Usage: source lib/tool-character.sh && tool_is_read_only "Read"

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ┌─────────────────────────────────────────────────────────────┐
# │ 도구 성격 데이터베이스                                         │
# │ Claude Code의 Tool 인터페이스에서 추출한 4가지 속성             │
# │ - isReadOnly:        읽기 전용? (상태 변경 없음)               │
# │ - isConcurrencySafe: 동시 실행 안전? (병렬 실행 가능)          │
# │ - isDestructive:     되돌릴 수 없는 변경? (rm, drop 등)       │
# │ - isIdempotent:      같은 입력 → 같은 결과? (반복 실행 안전)   │
# └─────────────────────────────────────────────────────────────┘

# 도구 성격 조회 (반환: "readOnly concurrencySafe destructive idempotent" — yes/no 4개)
tool_get_character() {
  local tool="$1"
  case "$tool" in
    # === 읽기 전용 도구 (병렬 실행 100% 안전) ===
    Read)           echo "yes yes no  yes" ;;
    Grep)           echo "yes yes no  yes" ;;
    Glob)           echo "yes yes no  yes" ;;
    WebSearch)      echo "yes yes no  no"  ;;  # 검색 결과가 달라질 수 있음
    WebFetch)       echo "yes yes no  no"  ;;

    # === 쓰기 도구 (동시 실행 주의) ===
    Edit)           echo "no  no  no  no"  ;;  # 같은 파일 동시 Edit → 충돌
    Write)          echo "no  no  no  yes" ;;  # 덮어쓰기이므로 idempotent
    NotebookEdit)   echo "no  no  no  no"  ;;

    # === 실행 도구 (파괴적 가능성) ===
    Bash)           echo "no  no  yes no"  ;;  # rm, drop 등 가능

    # === 에이전트/통신 도구 ===
    Agent)          echo "no  yes no  no"  ;;  # 에이전트 병렬 소환은 안전
    SendMessage)    echo "no  yes no  no"  ;;  # 메시지 전송은 병렬 안전
    TaskCreate)     echo "no  yes no  no"  ;;
    TaskStop)       echo "no  yes no  yes" ;;  # 중복 중단은 안전

    # === 기본값 (알 수 없는 도구 → 보수적) ===
    *)              echo "no  no  yes no"  ;;
  esac
}

# 개별 속성 조회 헬퍼
tool_is_read_only() {
  local char=$(tool_get_character "$1")
  [ "$(echo "$char" | awk '{print $1}')" = "yes" ]
}

tool_is_concurrency_safe() {
  local char=$(tool_get_character "$1")
  [ "$(echo "$char" | awk '{print $2}')" = "yes" ]
}

tool_is_destructive() {
  local char=$(tool_get_character "$1")
  [ "$(echo "$char" | awk '{print $3}')" = "yes" ]
}

tool_is_idempotent() {
  local char=$(tool_get_character "$1")
  [ "$(echo "$char" | awk '{print $4}')" = "yes" ]
}

# SOUL의 도구 목록에서 병렬 실행 안전성 판단
# soul_tools_concurrency_check <tools_csv>
# 반환: safe | caution | unsafe
soul_tools_concurrency_check() {
  local tools_csv="$1"
  local has_write=false
  local has_destructive=false

  # tools 파싱 (대괄호, 공백 제거)
  local tools=$(echo "$tools_csv" | tr -d '[]' | tr ',' '\n' | tr -d ' ')

  for tool in $tools; do
    [ -z "$tool" ] && continue
    if tool_is_destructive "$tool"; then
      has_destructive=true
    fi
    if ! tool_is_read_only "$tool" && ! tool_is_concurrency_safe "$tool"; then
      has_write=true
    fi
  done

  if [ "$has_destructive" = true ]; then
    echo "unsafe"
  elif [ "$has_write" = true ]; then
    echo "caution"
  else
    echo "safe"
  fi
}

# SOUL의 병렬 실행 가이드 생성 (Coordinator용)
# soul_concurrency_guide <soul_name>
soul_concurrency_guide() {
  local soul_name="$1"
  local soul_file=$(_resolve_soul_file "$soul_name")

  if [ ! -f "$soul_file" ]; then
    echo "[tool-char] ERROR: SOUL 없음: ${soul_name}"
    return 1
  fi

  soul_parse "$soul_file"
  local tools="${SOUL_TOOLS:-Read, Edit, Grep, Glob}"
  local safety=$(soul_tools_concurrency_check "$tools")

  echo "=== ${SOUL_NAME} 병렬 실행 가이드 ==="
  echo "  도구: [${tools}]"
  echo "  안전성: ${safety}"
  echo ""
  echo "  도구별 성격:"

  local tool_list=$(echo "$tools" | tr -d '[]' | tr ',' '\n' | tr -d ' ')
  printf "  %-14s %-10s %-12s %-12s %s\n" "Tool" "ReadOnly" "Concurrent" "Destructive" "Idempotent"
  printf "  %-14s %-10s %-12s %-12s %s\n" "----" "--------" "----------" "-----------" "----------"

  for tool in $tool_list; do
    [ -z "$tool" ] && continue
    local char=$(tool_get_character "$tool")
    local ro=$(echo "$char" | awk '{print $1}')
    local cs=$(echo "$char" | awk '{print $2}')
    local de=$(echo "$char" | awk '{print $3}')
    local id=$(echo "$char" | awk '{print $4}')
    printf "  %-14s %-10s %-12s %-12s %s\n" "$tool" "$ro" "$cs" "$de" "$id"
  done

  echo ""
  case "$safety" in
    safe)    echo "  결론: 읽기 전용 — 병렬 실행 안전" ;;
    caution) echo "  결론: 쓰기 도구 포함 — 파일 영역 분리 시 병렬 가능" ;;
    unsafe)  echo "  결론: 파괴적 도구 포함 — 직렬 실행 또는 worktree 격리 권장" ;;
  esac
}

# Coordinator용: 두 SOUL을 동시 실행할 수 있는지 판단
# can_run_parallel <soul1> <soul2>
can_run_parallel() {
  local soul1="$1"
  local soul2="$2"

  local file1=$(_resolve_soul_file "$soul1")
  local file2=$(_resolve_soul_file "$soul2")

  [ ! -f "$file1" ] || [ ! -f "$file2" ] && { echo "unknown"; return; }

  soul_parse "$file1"
  local tools1="${SOUL_TOOLS:-Read, Edit, Grep, Glob}"
  local safety1=$(soul_tools_concurrency_check "$tools1")

  soul_parse "$file2"
  local tools2="${SOUL_TOOLS:-Read, Edit, Grep, Glob}"
  local safety2=$(soul_tools_concurrency_check "$tools2")

  # 둘 다 safe → 병렬 OK
  if [ "$safety1" = "safe" ] && [ "$safety2" = "safe" ]; then
    echo "yes"
    return
  fi

  # 하나라도 unsafe → worktree 필요
  if [ "$safety1" = "unsafe" ] || [ "$safety2" = "unsafe" ]; then
    echo "worktree_required"
    return
  fi

  # caution → 파일 영역 분리 조건부 가능
  echo "conditional"
}
