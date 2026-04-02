#!/bin/bash
# session.sh — 세션 지속성 시스템 (작업 트랜스크립트 + 재개)
# Usage: source lib/session.sh && session_create "인증 API 구현" "nex,ryn,kai"

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 세션 디렉토리
SESSION_DIR="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/sessions"

# 세션 디렉토리 초기화
_session_ensure_dir() {
  [ ! -d "$SESSION_DIR" ] && mkdir -p "$SESSION_DIR"
}

# 태스크 설명 → 파일시스템 안전한 슬러그 변환
_task_slug() {
  local task="$1"
  echo "$task" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9가-힣-' | cut -c1-50
}

# 현재 타임스탬프 (ISO 8601)
_session_ts() {
  date -u +%Y-%m-%dT%H:%M:%S 2>/dev/null || date +%Y-%m-%dT%H:%M:%S
}

# 새 세션 생성
# session_create <task_description> <souls_csv>
session_create() {
  local task="$1"
  local souls_csv="$2"

  _session_ensure_dir

  # 기존 활성 세션이 있으면 종료
  local active_file="${SESSION_DIR}/active"
  if [ -f "$active_file" ]; then
    local prev=$(cat "$active_file" | tr -d '\r')
    if [ -n "$prev" ] && [ -f "${SESSION_DIR}/${prev}.meta" ]; then
      echo "[session] 이전 세션 자동 종료: ${prev}"
      session_end "superseded"
    fi
  fi

  local date_prefix=$(date +%Y-%m-%d)
  local slug=$(_task_slug "$task")
  local session_name="${date_prefix}_${slug}"
  local session_id="sess_$(date +%s)"
  local ts=$(_session_ts)

  # SOUL 목록을 JSON 배열로 변환
  local souls_json="["
  local soul_status_json="{"
  local first=true
  IFS=',' read -ra soul_arr <<< "$souls_csv"
  for s in "${soul_arr[@]}"; do
    s=$(echo "$s" | tr -d ' ')
    if [ "$first" = true ]; then
      souls_json="${souls_json}\"${s}\""
      soul_status_json="${soul_status_json}\"${s}\":\"idle\""
      first=false
    else
      souls_json="${souls_json},\"${s}\""
      soul_status_json="${soul_status_json},\"${s}\":\"idle\""
    fi
  done
  souls_json="${souls_json}]"
  soul_status_json="${soul_status_json}}"

  # 메타 파일 생성
  cat > "${SESSION_DIR}/${session_name}.meta" <<METAEOF
{"id":"${session_id}","task":"${task}","started":"${ts}","status":"active","souls":${souls_json},"soul_status":${soul_status_json},"last_updated":"${ts}"}
METAEOF

  # 트랜스크립트 파일 생성 (첫 엔트리: 세션 시작)
  echo "{\"ts\":\"${ts}\",\"soul\":\"system\",\"action\":\"session_start\",\"detail\":\"세션 생성: ${task}\"}" > "${SESSION_DIR}/${session_name}.jsonl"

  # 활성 세션 설정
  echo "$session_name" > "$active_file"

  echo "[session] 세션 생성: ${session_name}"
  echo "  ID: ${session_id}"
  echo "  태스크: ${task}"
  echo "  SOUL: ${souls_csv}"
}

# 현재 활성 세션 이름 반환
session_active() {
  local active_file="${SESSION_DIR}/active"
  if [ -f "$active_file" ]; then
    cat "$active_file" | tr -d '\r\n'
  else
    echo ""
  fi
}

# 세션 트랜스크립트에 이벤트 기록
# session_log <soul_name> <action> <detail>
session_log() {
  local soul_name="$1"
  local action="$2"
  local detail="$3"

  local active=$(session_active)
  if [ -z "$active" ]; then
    echo "[session] WARN: 활성 세션 없음, 기록 건너뜀"
    return 1
  fi

  local ts=$(_session_ts)
  detail=$(echo "$detail" | sed 's/\\/\\\\/g; s/"/\\"/g')

  echo "{\"ts\":\"${ts}\",\"soul\":\"${soul_name}\",\"action\":\"${action}\",\"detail\":\"${detail}\"}" >> "${SESSION_DIR}/${active}.jsonl"
}

# SOUL 상태 업데이트
# session_update_soul <soul_name> <new_status>
# status: idle | working | reviewing | done | failed | directing
session_update_soul() {
  local soul_name="$1"
  local new_status="$2"

  local active=$(session_active)
  if [ -z "$active" ]; then
    echo "[session] WARN: 활성 세션 없음"
    return 1
  fi

  local meta_file="${SESSION_DIR}/${active}.meta"
  if [ ! -f "$meta_file" ]; then
    echo "[session] ERROR: 메타 파일 없음: ${meta_file}"
    return 1
  fi

  # soul_status에서 해당 SOUL 상태 업데이트
  _sed_i "s/\"${soul_name}\":\"[^\"]*\"/\"${soul_name}\":\"${new_status}\"/" "$meta_file"

  # last_updated 갱신
  local ts=$(_session_ts)
  _sed_i "s/\"last_updated\":\"[^\"]*\"/\"last_updated\":\"${ts}\"/" "$meta_file"

  # 트랜스크립트에도 기록
  session_log "$soul_name" "status_change" "상태 변경: ${new_status}"
}

# 세션 종료
# session_end <final_status>
# final_status: completed | aborted | superseded
session_end() {
  local final_status="${1:-completed}"

  local active=$(session_active)
  if [ -z "$active" ]; then
    echo "[session] 활성 세션 없음"
    return 1
  fi

  local meta_file="${SESSION_DIR}/${active}.meta"
  if [ -f "$meta_file" ]; then
    _sed_i "s/\"status\":\"active\"/\"status\":\"${final_status}\"/" "$meta_file"
    local ts=$(_session_ts)
    _sed_i "s/\"last_updated\":\"[^\"]*\"/\"last_updated\":\"${ts}\"/" "$meta_file"
  fi

  # 종료 이벤트 기록
  session_log "system" "session_end" "세션 종료: ${final_status}"

  # 활성 링크 제거
  rm -f "${SESSION_DIR}/active"

  echo "[session] 세션 종료: ${active} (${final_status})"
}

# 세션 재개 (마지막 활성 세션 또는 가장 최근 세션)
session_resume() {
  _session_ensure_dir

  local active=$(session_active)

  # 활성 세션이 있으면 상태 출력
  if [ -n "$active" ] && [ -f "${SESSION_DIR}/${active}.meta" ]; then
    echo "[session] 활성 세션 발견: ${active}"
    session_status
    return 0
  fi

  # 활성 세션이 없으면 가장 최근 세션 찾기
  local latest_meta=$(ls -t "${SESSION_DIR}"/*.meta 2>/dev/null | head -1)
  if [ -z "$latest_meta" ]; then
    echo "[session] 재개할 세션 없음"
    return 1
  fi

  local latest_name=$(basename "$latest_meta" .meta)
  local status=$(grep -o '"status":"[^"]*"' "$latest_meta" | sed 's/"status":"//;s/"//')

  if [ "$status" = "completed" ] || [ "$status" = "aborted" ]; then
    echo "[session] 마지막 세션(${latest_name})은 이미 ${status} 상태"
    echo "  새 세션을 생성하세요."
    return 1
  fi

  # 세션 재활성화
  echo "$latest_name" > "${SESSION_DIR}/active"
  _sed_i "s/\"status\":\"[^\"]*\"/\"status\":\"active\"/" "$latest_meta"

  local ts=$(_session_ts)
  echo "{\"ts\":\"${ts}\",\"soul\":\"system\",\"action\":\"session_resume\",\"detail\":\"세션 재개\"}" >> "${SESSION_DIR}/${latest_name}.jsonl"

  echo "[session] 세션 재개: ${latest_name}"
  session_status
}

# 현재 세션 상태 출력
session_status() {
  local active=$(session_active)
  if [ -z "$active" ]; then
    echo "[session] 활성 세션 없음"
    return 1
  fi

  local meta_file="${SESSION_DIR}/${active}.meta"
  if [ ! -f "$meta_file" ]; then
    echo "[session] ERROR: 메타 파일 없음"
    return 1
  fi

  local task=$(grep -o '"task":"[^"]*"' "$meta_file" | sed 's/"task":"//;s/"//')
  local started=$(grep -o '"started":"[^"]*"' "$meta_file" | sed 's/"started":"//;s/"//')
  local status=$(grep -o '"status":"[^"]*"' "$meta_file" | sed 's/"status":"//;s/"//')
  local last_updated=$(grep -o '"last_updated":"[^"]*"' "$meta_file" | sed 's/"last_updated":"//;s/"//')

  echo "=== 세션 상태: ${active} ==="
  echo "  태스크: ${task}"
  echo "  상태: ${status}"
  echo "  시작: ${started}"
  echo "  최종 업데이트: ${last_updated}"
  echo ""

  # SOUL별 상태 (soul_status 파싱)
  echo "  SOUL 상태:"
  local soul_status_raw=$(grep -o '"soul_status":{[^}]*}' "$meta_file" | sed 's/"soul_status"://')
  echo "$soul_status_raw" | tr ',' '\n' | tr -d '{}' | while IFS= read -r pair; do
    [ -z "$pair" ] && continue
    local sname=$(echo "$pair" | cut -d: -f1 | tr -d '"')
    local sstatus=$(echo "$pair" | cut -d: -f2 | tr -d '"')
    printf "    %-10s %s\n" "$sname" "$sstatus"
  done

  # 최근 이벤트 (마지막 5개)
  echo ""
  echo "  최근 이벤트:"
  local transcript="${SESSION_DIR}/${active}.jsonl"
  if [ -f "$transcript" ]; then
    tail -5 "$transcript" | while IFS= read -r line; do
      [ -z "$line" ] && continue
      local ts=$(echo "$line" | grep -o '"ts":"[^"]*"' | sed 's/"ts":"//;s/"//' | sed 's/T/ /')
      local soul=$(echo "$line" | grep -o '"soul":"[^"]*"' | sed 's/"soul":"//;s/"//')
      local action=$(echo "$line" | grep -o '"action":"[^"]*"' | sed 's/"action":"//;s/"//')
      local detail=$(echo "$line" | grep -o '"detail":"[^"]*"' | sed 's/"detail":"//;s/"//')
      printf "    [%s] %s: %s — %s\n" "$ts" "$soul" "$action" "$detail"
    done
  fi
}

# 세션 목록
session_list() {
  _session_ensure_dir

  echo "=== GolemGarden Sessions ==="
  echo ""
  printf "%-30s %-12s %-20s %s\n" "Session" "Status" "Started" "Task"
  printf "%-30s %-12s %-20s %s\n" "-------" "------" "-------" "----"

  local active=$(session_active)

  for meta_file in "${SESSION_DIR}"/*.meta; do
    [ -f "$meta_file" ] || continue
    local name=$(basename "$meta_file" .meta)
    local task=$(grep -o '"task":"[^"]*"' "$meta_file" | sed 's/"task":"//;s/"//')
    local started=$(grep -o '"started":"[^"]*"' "$meta_file" | sed 's/"started":"//;s/"//' | sed 's/T/ /' | cut -c1-16)
    local status=$(grep -o '"status":"[^"]*"' "$meta_file" | sed 's/"status":"//;s/"//')

    # 활성 세션 표시
    local marker=""
    [ "$name" = "$active" ] && marker=" *"

    # 태스크 40자 제한
    local short_task=$(echo "$task" | cut -c1-40)

    printf "%-30s %-12s %-20s %s\n" "${name}${marker}" "$status" "$started" "$short_task"
  done
}
