#!/usr/bin/env bash
# soul-memory.sh — SOUL별 학습 기억 시스템
# 과거 태스크에서 배운 교훈을 기억하고, 유사 태스크 시 프롬프트에 자동 주입
# Usage: source lib/soul-memory.sh && memory_record ryn "JWT 인증" "refresh token 만료 시 새 토큰 발급 필요"

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${GOLEM_ROOT}/lib/soul-parser.sh"

# 메모리 디렉토리
MEMORY_DIR="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/memory"

# 메모리 디렉토리 초기화
_memory_ensure_dir() {
  [ ! -d "$MEMORY_DIR" ] && mkdir -p "$MEMORY_DIR"
}

# 학습 기억 기록
# memory_record <soul_name> <task_context> <lesson> [tags]
# tags: 콤마 구분 키워드 (검색/매칭용)
memory_record() {
  local soul_name="$1"
  local task_context="$2"
  local lesson="$3"
  local tags="${4:-}"

  _memory_ensure_dir

  local mem_file="${MEMORY_DIR}/${soul_name}.jsonl"
  local date=$(date +%Y-%m-%d)
  local ts=$(date -u +%Y-%m-%dT%H:%M:%S 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

  # 특수 문자 이스케이프
  lesson=$(echo "$lesson" | sed 's/\\/\\\\/g; s/"/\\"/g')
  task_context=$(echo "$task_context" | sed 's/\\/\\\\/g; s/"/\\"/g')

  local entry="{\"date\":\"${date}\",\"task\":\"${task_context}\",\"lesson\":\"${lesson}\",\"tags\":\"${tags}\",\"ts\":\"${ts}\"}"
  echo "$entry" >> "$mem_file"
  echo "[memory] ${soul_name}: 학습 기록 — ${lesson}"
}

# 태스크와 관련된 기억 검색 (키워드 매칭)
# memory_recall <soul_name> <task_keywords>
# 반환: 관련 기억 목록 (프롬프트 주입용)
memory_recall() {
  local soul_name="$1"
  local task_keywords="$2"
  local mem_file="${MEMORY_DIR}/${soul_name}.jsonl"

  if [ ! -f "$mem_file" ]; then
    return
  fi

  local matches=""
  local match_count=0

  # 키워드 상한 — 태스크 "전문"이 넘어오면 워드 수 × 기억 줄 수 × fork 5개가
  # 폭발해 MSYS(Windows)에서 사실상 행이 된다 (리뷰 프롬프트 60줄 × 기억 30건에서
  # 실측 15분+ 동결). 앞 400단어에서 4자 이상 고유 단어 최대 8개만 사용.
  local kw_list
  kw_list=$(printf '%s' "$task_keywords" | tr '[:space:]' '\n' \
    | awk 'NR>400{exit} length($0)>=4 && !seen[$0]++ {print}' | head -8)

  # 키워드별로 기억 검색 — 파일 단위 awk 1회 (라인 루프 × tr fork 제거).
  # index(tolower()): 고정 문자열 매칭이라 정규식 메타문자 태스크의 오매칭/폭주 차단.
  # 주의: grep -iF 는 Git Bash GNU grep 3.0 에서 조합 자체가 0매칭 버그 — 사용 금지.
  local keyword keyword_lower matched line lesson task date
  while IFS= read -r keyword; do
    [ -z "$keyword" ] && continue
    keyword_lower=$(printf '%s' "$keyword" | tr '[:upper:]' '[:lower:]')
    matched=$(awk -v kw="$keyword_lower" 'index(tolower($0), kw){print; c++} c>=5{exit}' "$mem_file" 2>/dev/null)
    [ -z "$matched" ] && continue

    while IFS= read -r line; do
      [ -z "$line" ] && continue
      lesson=$(echo "$line" | grep -o '"lesson":"[^"]*"' | sed 's/"lesson":"//;s/"//')
      task=$(echo "$line" | grep -o '"task":"[^"]*"' | sed 's/"task":"//;s/"//')
      date=$(echo "$line" | grep -o '"date":"[^"]*"' | sed 's/"date":"//;s/"//')

      # 중복 방지 (같은 lesson이 이미 있으면 건너뜀)
      if ! echo "$matches" | grep -qF "$lesson"; then
        matches="${matches}
- [${date}] ${task}: ${lesson}"
        match_count=$((match_count + 1))
      fi
      [ "$match_count" -ge 5 ] && break
    done <<EOF
$matched
EOF
    [ "$match_count" -ge 5 ] && break
  done <<EOF
$kw_list
EOF

  # 최대 5개까지만 반환 (프롬프트 토큰 절약)
  if [ "$match_count" -gt 0 ]; then
    echo "$matches" | head -6  # 첫 줄 빈줄 + 5개
  fi
}

# 프롬프트 주입용 기억 블록 생성
# memory_prompt_block <soul_name> <task>
memory_prompt_block() {
  local soul_name="$1"
  local task="$2"

  local recalls=$(memory_recall "$soul_name" "$task")

  if [ -z "$recalls" ] || [ "$recalls" = "" ]; then
    return
  fi

  cat <<MEMBLOCK

[이전 학습 기억 — ${soul_name}]
이 SOUL이 과거 유사한 작업에서 배운 교훈입니다. 참고하되 맹신하지 마세요:
${recalls}
MEMBLOCK
}

# SOUL의 전체 기억 조회
memory_list() {
  local soul_name="$1"
  local mem_file="${MEMORY_DIR}/${soul_name}.jsonl"

  if [ ! -f "$mem_file" ]; then
    echo "[memory] ${soul_name}: 기억 없음"
    return
  fi

  local count=$(wc -l < "$mem_file" | tr -d ' \r')
  echo "=== ${soul_name} 학습 기억 (${count}건) ==="
  echo ""
  printf "%-12s %-25s %s\n" "Date" "Task" "Lesson"
  printf "%-12s %-25s %s\n" "----" "----" "------"

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local date=$(echo "$line" | grep -o '"date":"[^"]*"' | sed 's/"date":"//;s/"//')
    local task=$(echo "$line" | grep -o '"task":"[^"]*"' | sed 's/"task":"//;s/"//' | cut -c1-23)
    local lesson=$(echo "$line" | grep -o '"lesson":"[^"]*"' | sed 's/"lesson":"//;s/"//' | cut -c1-50)
    printf "%-12s %-25s %s\n" "$date" "$task" "$lesson"
  done < "$mem_file"
}

# 기억 삭제 (인덱스 기반)
memory_forget() {
  local soul_name="$1"
  local line_num="$2"
  local mem_file="${MEMORY_DIR}/${soul_name}.jsonl"

  if [ ! -f "$mem_file" ]; then
    echo "[memory] ${soul_name}: 기억 없음"
    return 1
  fi

  _sed_i "${line_num}d" "$mem_file"
  echo "[memory] ${soul_name}: ${line_num}번째 기억 삭제"
}

# 전체 기억 대시보드
memory_dashboard() {
  _memory_ensure_dir

  echo "=== GolemGarden Memory Dashboard ==="
  echo ""
  printf "%-10s %-8s %s\n" "SOUL" "Count" "Latest"
  printf "%-10s %-8s %s\n" "----" "-----" "------"

  for mem_file in "${MEMORY_DIR}"/*.jsonl; do
    [ -f "$mem_file" ] || continue
    local name=$(basename "$mem_file" .jsonl)
    local count=$(wc -l < "$mem_file" | tr -d ' \r')
    count=${count:-0}
    local latest="—"
    if [ "$count" -gt 0 ]; then
      latest=$(tail -1 "$mem_file" | grep -o '"lesson":"[^"]*"' | sed 's/"lesson":"//;s/"//' | cut -c1-40)
    fi
    printf "%-10s %-8s %s\n" "$name" "${count}건" "$latest"
  done
}
