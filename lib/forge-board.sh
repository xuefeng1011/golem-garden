#!/usr/bin/env bash
# forge-board.sh — forge-board.md 자동 업데이트
# Usage: source lib/forge-board.sh && board_add_task "2026-04-09" "인증 API" "ryn" "success"

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# forge-board.md 경로 결정
_board_file() {
  local board="${GOLEM_DIR}/forge-board.md"
  [ -f "$board" ] && echo "$board" || echo ""
}

# 안전한 awk 덮어쓰기 (mktemp 사용 — 병렬 실행 시 race condition 방지)
_board_awk_replace() {
  local board="$1"
  shift
  local tmpf
  tmpf=$(mktemp "${board}.XXXXXX") || return 1
  awk "$@" "$board" > "$tmpf" && mv "$tmpf" "$board" || { rm -f "$tmpf"; return 1; }
}

# updated: 타임스탬프 갱신
board_update_timestamp() {
  local board=$(_board_file)
  [ -z "$board" ] && return 0
  local today=$(date +%Y-%m-%d)
  if grep -q "^updated:" "$board" 2>/dev/null; then
    _sed_i "s/^updated:[[:space:]]*.*/updated: ${today}/" "$board"
  fi
}

# 팀 구성 테이블에서 SOUL의 Rank 컬럼 업데이트
# Usage: board_update_rank <soul_name> <new_rank>
board_update_rank() {
  local soul_name="$1"
  local new_rank="$2"
  local board=$(_board_file)
  [ -z "$board" ] && return 0

  local escaped_name=$(printf '%s' "$soul_name" | sed 's/[.[\*^$/]/\\&/g')
  local pattern="^|[[:space:]]*${escaped_name}[[:space:]]*|"

  if grep -qi "$pattern" "$board" 2>/dev/null; then
    _board_awk_replace "$board" -v soul="$soul_name" -v rank="$new_rank" '{
      lsoul = tolower(soul)
      if (tolower($0) ~ "^[|][[:space:]]*" lsoul "[[:space:]]*[|]") {
        n = split($0, fields, "|")
        if (n >= 7) {
          fields[6] = " " rank " "
          line = ""
          for (i = 1; i <= n; i++) {
            if (i > 1) line = line "|"
            line = line fields[i]
          }
          print line
        } else {
          print $0
        }
      } else {
        print $0
      }
    }'

    board_update_timestamp
    echo "[board] ${soul_name} 랭크 업데이트: ${new_rank}"
  fi
}

# 팀 구성 테이블에서 SOUL의 상태 컬럼 업데이트
# Usage: board_update_status <soul_name> <status>
board_update_status() {
  local soul_name="$1"
  local new_status="$2"
  local board=$(_board_file)
  [ -z "$board" ] && return 0

  local escaped_name=$(printf '%s' "$soul_name" | sed 's/[.[\*^$/]/\\&/g')
  local pattern="^|[[:space:]]*${escaped_name}[[:space:]]*|"

  if grep -qi "$pattern" "$board" 2>/dev/null; then
    _board_awk_replace "$board" -v soul="$soul_name" -v status="$new_status" '{
      lsoul = tolower(soul)
      if (tolower($0) ~ "^[|][[:space:]]*" lsoul "[[:space:]]*[|]") {
        n = split($0, fields, "|")
        if (n >= 8) {
          fields[7] = " " status " "
          line = ""
          for (i = 1; i <= n; i++) {
            if (i > 1) line = line "|"
            line = line fields[i]
          }
          print line
        } else {
          print $0
        }
      } else {
        print $0
      }
    }'

    board_update_timestamp
  fi
}

# 태스크 히스토리에 새 행 추가
# Usage: board_add_task <date> <task> <soul_name> <result> [note]
board_add_task() {
  local date="$1"
  local task="$2"
  local soul_name="$3"
  local result="$4"
  local note="${5:-}"
  local board=$(_board_file)
  [ -z "$board" ] && return 0

  # 태스크 설명에서 파이프 문자 이스케이프 (테이블 깨짐 방지)
  task=$(printf '%s' "$task" | sed 's/|/∣/g')
  note=$(printf '%s' "$note" | sed 's/|/∣/g')

  local new_row="| ${date} | ${task} | ${soul_name} | ${result} | ${note} |"

  # "(자동 누적)" 플레이스홀더가 있으면 교체, 없으면 테이블 끝에 추가
  if grep -q "(자동 누적)" "$board" 2>/dev/null; then
    # sed replacement string에서 특수문자 이스케이프
    local escaped_row
    escaped_row=$(printf '%s' "$new_row" | sed 's/[&/\\]/\\&/g')
    _sed_i "s/^|.*[(]자동 누적[)].*/${escaped_row}/" "$board"
  else
    _board_awk_replace "$board" -v row="$new_row" '
    /^## 태스크 히스토리/ { in_section=1 }
    in_section && /^[|]/ { last_table_line=NR }
    { lines[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        print lines[i]
        if (i == last_table_line) {
          print row
        }
      }
    }'
  fi

  board_update_timestamp
  echo "[board] 태스크 기록: ${soul_name} — ${task} (${result})"
}

# 팀 구성 테이블에 새 SOUL 행 추가
# Usage: board_add_soul <name> <role> <omc_agent> <model> <rank> <status>
board_add_soul() {
  local name="$1"
  local role="$2"
  local omc_agent="$3"
  local model="$4"
  local rank="${5:-novice}"
  local status="${6:-active}"
  local board=$(_board_file)
  [ -z "$board" ] && return 0

  # 이미 등록되어 있으면 스킵
  if grep -qi "^|[[:space:]]*${name}[[:space:]]*|" "$board" 2>/dev/null; then
    echo "[board] ${name} 이미 등록됨 — 스킵"
    return 0
  fi

  local new_row="| ${name} | ${role} | ${omc_agent} | ${model} | ${rank} | ${status} |"

  # 팀 구성 테이블의 마지막 데이터 행 뒤에 추가
  _board_awk_replace "$board" -v row="$new_row" '
  /^## 팀 구성/ { in_section=1 }
  in_section && /^[|]/ && !/^[|][-[:space:]|]+$/ && !/[|] SOUL / { last_data=NR }
  in_section && /^$/ && last_data > 0 { in_section=0 }
  { lines[NR] = $0 }
  END {
    for (i = 1; i <= NR; i++) {
      print lines[i]
      if (i == last_data) {
        print row
      }
    }
  }'

  board_update_timestamp
  echo "[board] 새 SOUL 추가: ${name} (${role})"
}
