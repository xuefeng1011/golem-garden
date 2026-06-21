#!/usr/bin/env bash
# explore.sh — grep-first 코드베이스 컨텍스트 도구 (CodeGraph 경량판)
# Usage: source lib/explore.sh && explore_run "agent_run" [path]
#        source lib/explore.sh && explore_files "mission_" [path]
#
# 단일 호출로 COMPLETE 컨텍스트를 번들링해 SOULs의 반복 grep을 제거.
# rg(ripgrep) 우선, 없으면 grep -r 폴백.

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── 설정 ──
EXPLORE_MAX_FILES="${EXPLORE_MAX_FILES:-10}"    # 출력할 최대 파일 수
EXPLORE_MAX_LINES="${EXPLORE_MAX_LINES:-200}"   # 번들 총 출력 라인 상한
EXPLORE_CONTEXT_LINES="${EXPLORE_CONTEXT_LINES:-2}"  # 매칭 전후 컨텍스트

# grep 제외 경로 (rg는 .gitignore 자동 적용, grep 폴백 시 수동 제외)
_EXPLORE_EXCLUDES=(
  ".git"
  "node_modules"
  "dist"
  "__pycache__"
  ".golem/sessions"
  ".omc"
  ".vite"
)

# ── 백엔드 감지 ──
_explore_backend() {
  if command -v rg >/dev/null 2>&1; then
    echo "rg"
  else
    echo "grep"
  fi
}

# ── 파일별 매치 수 집계: "<count>\t<file>" 형식으로 stdout ──
# _explore_count_matches <query> <search_path>
_explore_count_matches() {
  local query="$1"
  local search_path="$2"
  local backend
  backend=$(_explore_backend)

  if [ "$backend" = "rg" ]; then
    # rg: .gitignore 자동 적용, 바이너리 제외
    rg --count --color=never -- "$query" "$search_path" 2>/dev/null \
      | grep -v '^Binary file' \
      | sed 's/:\([0-9]*\)$/\t\1/' \
      | awk -F'\t' '{print $2"\t"$1}'
  else
    # grep 폴백: 제외 경로 수동 지정
    local excludes=()
    for ex in "${_EXPLORE_EXCLUDES[@]}"; do
      excludes+=(--exclude-dir="$ex")
    done
    grep -r --include='*' "${excludes[@]}" -c -- "$query" "$search_path" 2>/dev/null \
      | grep -v ':0$' \
      | sed 's/:\([0-9]*\)$/\t\1/' \
      | awk -F'\t' '{print $2"\t"$1}'
  fi
}

# ── 파일별 매치 라인(컨텍스트 포함): "<file>:<line>:<text>" 형식 ──
# _explore_match_lines <query> <file>
_explore_match_lines() {
  local query="$1"
  local file="$2"
  local ctx="${EXPLORE_CONTEXT_LINES}"
  local backend
  backend=$(_explore_backend)

  if [ "$backend" = "rg" ]; then
    rg --color=never --no-heading --line-number -C "$ctx" -- "$query" "$file" 2>/dev/null
  else
    grep -n -C "$ctx" -- "$query" "$file" 2>/dev/null
  fi
}

# ── 정의 라인 탐색 (함수/변수 선언 등) ──
# _explore_definition_line <query> <file> — 가장 그럴듯한 정의 라인 1개 반환
_explore_definition_line() {
  local query="$1"
  local file="$2"
  # Bash 함수, Python def, 변수 할당, Arrow function, 일반 함수 선언 패턴
  grep -nE \
    "(^|\s)(function\s+${query}|${query}\s*\(\)|def\s+${query}|${query}\s*=\s*(function|\(|{)|${query}\s*\(\s*\{)" \
    "$file" 2>/dev/null | head -1
}

# ═══════════════════════════════════════════════════════
# explore_files <query> [path]
# 랭크된 파일 목록만 출력 (매치 수 포함). body 없음.
# ═══════════════════════════════════════════════════════
explore_files() {
  local query="$1"
  local search_path="${2:-${GOLEM_PROJECT:-${GOLEM_ROOT}}}"
  local backend
  backend=$(_explore_backend)

  if [ -z "$query" ]; then
    echo "[explore] 사용법: explore_files <query> [path]" >&2
    return 1
  fi

  # 매치 수 집계 후 내림차순 정렬
  local ranked
  ranked=$(_explore_count_matches "$query" "$search_path" \
    | sort -t$'\t' -k1 -rn)

  local total_files
  total_files=$(echo "$ranked" | grep -c '.' 2>/dev/null || echo 0)

  echo "=== explore_files: \"${query}\" — backend: ${backend} ==="
  echo "총 ${total_files}개 파일 (상위 ${EXPLORE_MAX_FILES}개 표시)"
  echo ""

  local n=0
  while IFS=$'\t' read -r count file; do
    [ -z "$file" ] && continue
    n=$(( n + 1 ))
    [ "$n" -gt "$EXPLORE_MAX_FILES" ] && break
    printf "  %3d matches  %s\n" "$count" "$file"
  done <<< "$ranked"

  if [ "$total_files" -gt "$EXPLORE_MAX_FILES" ]; then
    echo "[truncated: 상위 ${EXPLORE_MAX_FILES}개 / 전체 ${total_files}개]"
  fi
  return 0
}

# ═══════════════════════════════════════════════════════
# explore_run <query> [path]
# 전체 컨텍스트 번들 출력: 요약 헤더 → 파일 목록 → 상세 블록
# ═══════════════════════════════════════════════════════
explore_run() {
  local query="$1"
  local search_path="${2:-${GOLEM_PROJECT:-${GOLEM_ROOT}}}"
  local backend
  backend=$(_explore_backend)

  if [ -z "$query" ]; then
    echo "[explore] 사용법: explore_run <query> [path]" >&2
    return 1
  fi

  # 1. 파일별 매치 수 집계 + 내림차순 정렬
  local ranked
  ranked=$(_explore_count_matches "$query" "$search_path" \
    | sort -t$'\t' -k1 -rn)

  local total_files total_matches
  total_files=$(echo "$ranked" | grep -c '[^\s]' 2>/dev/null || echo 0)
  total_matches=$(echo "$ranked" | awk -F'\t' '{s+=$1} END{print s+0}')

  # 2. 요약 헤더
  echo "╔══════════════════════════════════════════════════"
  echo "║ explore: \"${query}\""
  printf "║ %d files, %d total matches  [backend: %s]\n" \
    "$total_files" "$total_matches" "$backend"
  echo "╚══════════════════════════════════════════════════"
  echo ""

  if [ "$total_files" -eq 0 ]; then
    echo "(no matches)"
    return 0
  fi

  # 3. 랭킹 맵 (summary map)
  echo "── Ranked file map ──"
  local n=0
  while IFS=$'\t' read -r count file; do
    [ -z "$file" ] && continue
    n=$(( n + 1 ))
    [ "$n" -gt "$EXPLORE_MAX_FILES" ] && break
    printf "  #%-2d  %3d matches  %s\n" "$n" "$count" "$file"
  done <<< "$ranked"
  if [ "$total_files" -gt "$EXPLORE_MAX_FILES" ]; then
    echo "  ... [${total_files} 파일 중 상위 ${EXPLORE_MAX_FILES}개만 표시]"
  fi
  echo ""

  # 4. 파일별 상세 블록
  echo "── Detail blocks ──"
  local lines_emitted=0
  local truncated=0
  n=0

  while IFS=$'\t' read -r count file; do
    [ -z "$file" ] && continue
    n=$(( n + 1 ))
    [ "$n" -gt "$EXPLORE_MAX_FILES" ] && break

    if [ "$lines_emitted" -ge "$EXPLORE_MAX_LINES" ]; then
      truncated=1
      break
    fi

    echo ""
    echo "=== ${file} (${count} matches) ==="
    lines_emitted=$(( lines_emitted + 1 ))

    # 정의 라인 우선 표시
    local def_line
    def_line=$(_explore_definition_line "$query" "$file")
    if [ -n "$def_line" ]; then
      echo "  [def] ${def_line}"
      lines_emitted=$(( lines_emitted + 1 ))
    fi

    # 매칭 라인 + 컨텍스트 출력 (라인 예산 내)
    local block_lines=0
    local budget=$(( EXPLORE_MAX_LINES - lines_emitted ))
    [ "$budget" -le 0 ] && truncated=1 && break

    while IFS= read -r line; do
      echo "  ${line}"
      block_lines=$(( block_lines + 1 ))
      if [ "$block_lines" -ge "$budget" ]; then
        echo "  [truncated: 라인 예산 초과]"
        truncated=1
        break
      fi
    done < <(_explore_match_lines "$query" "$file")

    lines_emitted=$(( lines_emitted + block_lines ))
  done <<< "$ranked"

  echo ""
  if [ "$truncated" -eq 1 ]; then
    echo "[truncated: EXPLORE_MAX_LINES=${EXPLORE_MAX_LINES} 도달 — 전체 보려면 EXPLORE_MAX_LINES=500 설정]"
  else
    echo "[완료: ${lines_emitted} 라인, ${n}개 파일 표시]"
  fi
  return 0
}
