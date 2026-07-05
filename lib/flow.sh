#!/usr/bin/env bash
# flow.sh — Flow Engine 실행 계층
# 의존: flow-contract.sh, flow-dag.sh, agent-runner.sh

# shellcheck disable=SC1090
source "${GOLEM_ROOT}/lib/flow-contract.sh"
source "${GOLEM_ROOT}/lib/flow-dag.sh"
source "${GOLEM_ROOT}/lib/agent-runner.sh"

# FLOW_DIR는 flow-dag.sh에서 정의됨

# ── 내부 헬퍼: 플로우 레벨 status 변경 ───────────────────────────────────────
# _flow_set_flow_status <state_file> <new_status>
_flow_set_flow_status() {
  local state_file="$1" new_status="$2"
  [ -f "$state_file" ] || return 1
  _flow_lock "$state_file" || return 1
  local rc=0
  local json
  json=$(tr -d '\n\r' < "$state_file")
  local head="${json%%\"steps\"*}"
  local rest="${json#*\"steps\"}"
  local new_head
  new_head=$(printf '%s' "$head" | \
    sed "s/\"status\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"status\":\"${new_status}\"/")
  local updated="${new_head}\"steps\"${rest}"
  local tmp="${state_file}.tmp.$$"
  printf '%s' "$updated" > "$tmp" && mv -f "$tmp" "$state_file" || rc=1
  _flow_unlock "$state_file"
  return "$rc"
}

# ── 데이터 전달: {{step_id}} 치환 ──────────────────────────────────────────────
# JSON 이스케이프된 output 을 실제 텍스트로 복원 (\n→줄바꿈, \"→", \\→\)
_flow_unescape() {
  printf '%s' "$1" | sed -e 's/\\"/"/g' -e 's/\\n/\
/g' -e 's/\\\\/\\/g'
}

# _flow_subst <state_file> <text> — text 내 {{<step_id>}} 를 그 step 의 저장된
# output 으로 리터럴 치환(완료된 step 만). bash ${//} 리터럴 — 정규식/특수문자 안전.
_flow_subst() {
  local state_file="$1" text="$2"
  local ids id out
  # _fc_get_field 는 개행을 안 붙이므로(printf '%s') 명시적으로 줄바꿈 추가 —
  # 안 하면 id 들이 'in1a1' 로 붙어 치환 매칭이 깨진다.
  ids=$(_fc_steps_lines < "$state_file" | while IFS= read -r l; do
    [ -n "$l" ] && { _fc_get_field id "$l"; echo; }
  done)
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    case "$text" in
      *"{{$id}}"*) : ;;
      *) continue ;;
    esac
    out=$(flow_step_output "$state_file" "$id" 2>/dev/null)
    out=$(_flow_unescape "$out")
    text="${text//"{{$id}}"/$out}"
  done <<EOF
$ids
EOF
  printf '%s' "$text"
}

# ── 라이프사이클 마커 헬퍼 ────────────────────────────────────────────────────
# stdout 마커 계약 (웹 클라이언트가 정규식 파싱 — 형식 변경 금지):
#   ^\[FLOW\]\[(RUN|STEP)\]\[([^\]]+)\](?:\[([^\]]+)\])?\s*(.*)$
# step id 는 [A-Za-z0-9_-]+ (flow_validate_steps), soul 은 SOUL 파일명 슬러그 —
# ']' 가 포함될 수 없어 브래킷 파싱이 항상 안전하다.

# 마커용 미리보기 — 개행 제거 + N자 절단(C 로케일 바이트 절단 대비 UTF-8 꼬리 정리)
_flow_marker_snip() {
  local text="$1" len="${2:-80}"
  text=$(printf '%s' "$text" | tr '\n\r' '  ')
  text="${text:0:$len}"
  _flow_utf8_sanitize "$text"
}

# ── 플로우 컨텍스트 주입 ──────────────────────────────────────────────────────
# agent 단계 task 에 플로우 목표/현재 단계 헤더를 프리펜드 — 에이전트가 전체
# 맥락 없이 저장 경로를 되묻는 문제 방지. 산출물 저장 규칙 줄은
# GOLEM_FLOW_OUTPUT_DIR(명시적 override, studio_run 이 설정) 이 있으면 그 값,
# 없고 GOLEM_PROJECT/studio.json 이 존재하면 GOLEM_PROJECT/output 을 기본값으로
# 딱 한 줄만 추가한다 (UI가 studio_run 을 안 거치고 flow_run 을 직접 호출해도
# 동일 규칙이 적용되도록 — BACKLOG P0-1).
# {{}} 치환이 끝난 task 에 프리펜드한다 (치환 순서 불변).
_flow_prepend_context() {
  local state_file="$1" step_id="$2" task="$3"
  local json head goal
  json=$(tr -d '\n\r' < "$state_file")
  head="${json%%\"steps\"*}"
  goal=$(_json_unescape "$(_json_get_string "$head" goal)")
  local ctx="[플로우 컨텍스트]
- 플로우 목표: ${goal}
- 현재 단계: ${step_id}"

  # 산출물 디렉토리(단일 유효값) — 명시적 env(GOLEM_FLOW_OUTPUT_DIR)가 우선.
  # 미설정이고 GOLEM_PROJECT가 스튜디오(studio.json 존재)면 <project>/output을
  # 기본 적용 — UI가 studio_run 을 거치지 않고 flow_run 을 직접 호출해도
  # 저장 규칙이 에이전트에게 전달되도록 한다 (BACKLOG P0-1).
  local out_dir="${GOLEM_FLOW_OUTPUT_DIR:-}"
  if [ -z "$out_dir" ] && [ -n "${GOLEM_PROJECT:-}" ] && [ -f "${GOLEM_PROJECT}/studio.json" ]; then
    out_dir="${GOLEM_PROJECT}/output"
    mkdir -p "$out_dir" 2>/dev/null || true
  fi

  if [ -n "$out_dir" ]; then
    ctx="${ctx}
- 파일 산출물은 반드시 '${out_dir}' 디렉토리 아래에 저장하라. 저장 경로를 사용자에게 묻지 마라."
  fi
  printf '%s\n\n---\n\n%s' "$ctx" "$task"
}

# 재시도 백오프 초 계산 (순수 함수, 테스트용) — base * 2^(attempt-1), 최대 30s.
# 레이트리밋 시 즉시 재소환으로 토큰 낭비/한도 악화를 막는다.
# GOLEM_FLOW_RETRY_BASE_SEC=0 이면 0 반환(백오프 비활성 — bats 고속화).
_flow_retry_backoff_secs() {
  local attempt="$1"
  local base="${GOLEM_FLOW_RETRY_BASE_SEC:-2}"
  printf '%s' "$attempt" | grep -qE '^[1-9][0-9]*$' || { echo 0; return 0; }
  [ "$base" -le 0 ] 2>/dev/null && { echo 0; return 0; }
  local secs=$(( base * (1 << (attempt - 1)) ))
  [ "$secs" -gt 30 ] && secs=30
  echo "$secs"
}

# ── 1. flow_step_run ──────────────────────────────────────────────────────────
# flow_step_run <flow_id> <step_id>
flow_step_run() {
  local flow_id="$1" step_id="$2"
  local state_file="${FLOW_DIR}/${flow_id}/state.json"
  [ -f "$state_file" ] || { echo "[ERROR] flow_step_run: state.json 없음" >&2; return 1; }

  local step_line
  # -F: step_id의 정규식 메타문자 오매칭 차단 (_fc_steps_lines가 공백 정규화 보장)
  step_line=$(_fc_steps_lines < "$state_file" | grep -F "\"id\":\"${step_id}\"")
  [ -z "$step_line" ] && { echo "[ERROR] flow_step_run: step '${step_id}' 없음" >&2; return 1; }

  local soul task retry on_fail type
  soul=$(_fc_get_field "soul" "$step_line")
  task=$(_fc_get_field "task" "$step_line")
  retry=$(_fc_get_field "retry" "$step_line")
  on_fail=$(_fc_get_field "on_fail" "$step_line")
  type=$(_fc_get_field "type" "$step_line")
  retry=${retry:-0}; on_fail=${on_fail:-abort}; type=${type:-agent}

  flow_set_step_status "$state_file" "$step_id" "running"

  # 입력 노드 — task 값이 곧 출력(하류로 흐름). agent 소환 없음.
  if [ "$type" = "input" ]; then
    printf '[FLOW][STEP][%s][INPUT] 시작: %s\n' "$step_id" "$(_flow_marker_snip "$task")"
    printf 'INPUT:%s\n' "$task"
    flow_set_step_output "$state_file" "$step_id" "$task"
    flow_set_step_status "$state_file" "$step_id" "done"
    printf '[FLOW][STEP][%s] 완료\n' "$step_id"
    return 0
  fi

  # 상류 단계 출력 주입 ({{id}} 치환) — input/agent 출력이 task 로 흐름
  task=$(_flow_subst "$state_file" "$task")

  if [ -z "$soul" ]; then
    printf '[FLOW][STEP][%s][HOST] 시작: %s\n' "$step_id" "$(_flow_marker_snip "$task")"
    printf 'HOST:%s\n' "$task"
    flow_set_step_output "$state_file" "$step_id" "$task"
    flow_set_step_status "$state_file" "$step_id" "done"
    printf '[FLOW][STEP][%s] 완료\n' "$step_id"
    return 0
  fi

  printf '[FLOW][STEP][%s][%s] 시작: %s\n' "$step_id" "$soul" "$(_flow_marker_snip "$task")"

  # 플로우 컨텍스트 헤더 프리펜드 — {{}} 치환 완료 후 (마커 미리보기는 원래 task)
  task=$(_flow_prepend_context "$state_file" "$step_id" "$task")

  local attempt=0 rc=0 _out=""
  while true; do
    # 출력 캡처 후 재출력 — run_id 추출(단계별 결과 보기) + SSE 로그 보존.
    # if 분기로 호출 — `cmd; rc=$?`는 set -e(bats/forge.sh) 환경에서 즉사한다
    if _out=$(agent_run "$soul" "$task" 2>/dev/null); then rc=0; else rc=$?; fi
    printf '%s\n' "$_out"
    [ "$rc" -eq 0 ] && break
    attempt=$((attempt + 1))
    if [ "$attempt" -gt "$retry" ]; then break; fi
    # 재시도 전 지수 백오프 (레이트리밋 완화)
    local _bk; _bk=$(_flow_retry_backoff_secs "$attempt")
    [ "${_bk:-0}" -gt 0 ] 2>/dev/null && sleep "$_bk"
  done

  # <usage> ... run=<uuid> ... 에서 run_id 추출해 step 에 기록 (단계 클릭 시 결과 조회)
  local _step_run
  _step_run=$(printf '%s' "$_out" | grep -o 'run=[0-9a-fA-F-]\{8,\}' | head -1 | sed 's/run=//')
  [ -n "$_step_run" ] && flow_set_step_run_id "$state_file" "$step_id" "$_step_run" 2>/dev/null || true

  # 산출 텍스트 캡처(= _out 에서 <usage> 라인 제거) → 하류 {{id}} 치환용 + 결과 표시
  local _out_text
  _out_text=$(printf '%s\n' "$_out" | sed '/^<usage>/d')
  flow_set_step_output "$state_file" "$step_id" "$_out_text" 2>/dev/null || true

  if [ "$rc" -eq 0 ]; then
    flow_set_step_status "$state_file" "$step_id" "done"
    printf '[FLOW][STEP][%s] 완료\n' "$step_id"
    return 0
  fi

  local _reason
  _reason=$(_flow_marker_snip "$_out" 120)
  [ -z "${_reason// /}" ] && _reason="agent_run rc=${rc}"
  printf '[FLOW][STEP][%s] 실패: %s\n' "$step_id" "$_reason"

  flow_set_step_status "$state_file" "$step_id" "failed"
  if [ "$on_fail" = "continue" ]; then
    return 0
  elif [ "${on_fail#goto:}" != "$on_fail" ]; then
    # goto 가드: target이 이미 failed(자기 자신 포함)면 abort로 격하 —
    # goto 사이클이 max_iter까지 SOUL을 반복 소환하는 폭주 방지 (리뷰 HIGH-3)
    local goto_target tgt_line tgt_status
    goto_target="${on_fail#goto:}"
    tgt_line=$(_fc_steps_lines < "$state_file" | grep -F "\"id\":\"${goto_target}\"")
    tgt_status=$(_fc_get_field "status" "$tgt_line")
    if [ "$tgt_status" = "failed" ]; then
      echo "[FLOW] goto 격하: target '${goto_target}' 이미 failed — abort 처리" >&2
      _flow_set_flow_status "$state_file" "failed"
      return 1
    fi
    flow_set_step_status "$state_file" "$goto_target" "pending" 2>/dev/null || true
    return 0
  else
    _flow_set_flow_status "$state_file" "failed"
    return 1
  fi
}

# ── 2. flow_approve ───────────────────────────────────────────────────────────
# flow_approve <flow_id> <step_id>
flow_approve() {
  local flow_id="$1" step_id="$2"
  local state_file="${FLOW_DIR}/${flow_id}/state.json"
  [ -f "$state_file" ] || { echo "[ERROR] flow_approve: state.json 없음" >&2; return 1; }
  # "pending"으로 되돌리면 approval=true라 다시 승인 대기로 빠짐(라이브락) —
  # "approved"는 flow_next_ready가 일반 ready로 취급한다
  flow_set_step_status "$state_file" "$step_id" "approved"
}

# ── 3. flow_reject ────────────────────────────────────────────────────────────
# flow_reject <flow_id> <step_id>
flow_reject() {
  local flow_id="$1" step_id="$2"
  local state_file="${FLOW_DIR}/${flow_id}/state.json"
  [ -f "$state_file" ] || { echo "[ERROR] flow_reject: state.json 없음" >&2; return 1; }
  flow_set_step_status "$state_file" "$step_id" "skipped"
}

# ── 4. flow_run ───────────────────────────────────────────────────────────────
# flow_run <flow_id>
flow_run() {
  local flow_id="$1"
  local state_file="${FLOW_DIR}/${flow_id}/state.json"
  [ -f "$state_file" ] || { echo "[ERROR] flow_run: state.json 없음" >&2; return 1; }

  local total_steps
  total_steps=$(_fc_steps_lines < "$state_file" | grep -c '"id"')
  printf '[FLOW][RUN][%s] 시작 (steps=%s)\n' "$flow_id" "$total_steps"

  # 고아 running self-heal — 이전 실행이 타임아웃/중지/크래시로 죽으면 step 이
  # running 으로 고착되고 flow_next_ready 가 이를 건너뛰어 재실행이 영구 정지한다.
  # flow_run 은 flow 당 단일 실행 주체 전제 — 진입 시점의 running 은 전부
  # 죽은 실행의 잔재이므로 pending 으로 되돌려 재실행 대상으로 복구한다.
  local _orphan_line _orphan_id
  while IFS= read -r _orphan_line; do
    [ -z "$_orphan_line" ] && continue
    _orphan_id=$(_fc_get_field "id" "$_orphan_line")
    [ -z "$_orphan_id" ] && continue
    printf '[FLOW] 고아 running 복구: %s → pending\n' "$_orphan_id"
    flow_set_step_status "$state_file" "$_orphan_id" "pending"
  done <<EOF
$(_fc_steps_lines < "$state_file" | grep '"status":"running"')
EOF

  local ready_lines got_approval got_abort step_id prefix
  local has_unfinished has_failed
  local max_iter=$(( total_steps * 5 )); [ "$max_iter" -lt 5 ] && max_iter=5
  local iter=0
  while [ "$iter" -lt "$max_iter" ]; do
    iter=$((iter + 1))
    got_approval=0
    got_abort=0
    ready_lines=$(flow_next_ready "$state_file") || break
    if [ -z "$ready_lines" ]; then
      # 미종결(pending/승인대기/승인됨/실행중) step이 하나라도 남았으면
      # 플로우 status를 건드리지 않고 중단 — waiting_approval만 남은 플로우를
      # completed로 오기록하던 회귀 방지 (리뷰 HIGH-2)
      has_unfinished=$(_fc_steps_lines < "$state_file" | \
        grep -cE '"status":"(pending|waiting_approval|approved|running)"' 2>/dev/null) || has_unfinished=0
      [ "${has_unfinished:-0}" -gt 0 ] && break
      has_failed=$(_fc_steps_lines < "$state_file" | \
        grep -c '"status":"failed"' 2>/dev/null) || has_failed=0
      if [ "${has_failed:-0}" -gt 0 ]; then
        _flow_set_flow_status "$state_file" "failed"
      else
        _flow_set_flow_status "$state_file" "completed"
      fi
      break
    fi
    while IFS= read -r step_id; do
      [ -z "$step_id" ] && continue
      case "$step_id" in
        APPROVAL:*)
          prefix="${step_id#APPROVAL:}"
          flow_set_step_status "$state_file" "$prefix" "waiting_approval"
          printf '[FLOW] 승인 대기: step=%s\n  → flow_approve %s %s\n' \
            "$prefix" "$flow_id" "$prefix"
          got_approval=1 ;;
        *)
          # abort(rc 1) 시 같은 ready 그룹의 잔여 step 실행 중단 (리뷰 HIGH-1)
          if ! flow_step_run "$flow_id" "$step_id"; then
            got_abort=1
            break
          fi ;;
      esac
    done <<EOF
$ready_lines
EOF
    [ "$got_abort" -eq 1 ] && break
    [ "$got_approval" -eq 1 ] && break
  done

  # 종료 마커 — 최종 플로우 status 기준. 승인 대기 등 미종결 상태는 기존
  # '[FLOW] 승인 대기' 메시지 그대로 두고 RUN 종료 마커를 내지 않는다.
  # rc 계약: failed → 1, completed·승인 대기(미종결) → 0. 승인 대기는 정상
  # 흐름의 일시정지이지 실패가 아니다. studio_run/forge.sh 가 이 rc 를 전파한다.
  local _final
  _final=$(tr -d '\n\r' < "$state_file")
  _final="${_final%%\"steps\"*}"
  _final=$(printf '%s' "$_final" | grep -o '"status":"[a-z_]*"' | head -1 | sed 's/.*:"//;s/"$//')
  case "$_final" in
    completed) printf '[FLOW][RUN][%s] 완료\n' "$flow_id" ;;
    failed)    printf '[FLOW][RUN][%s] 실패\n' "$flow_id"; return 1 ;;
  esac
  return 0
}

# ── 5. flow_status ────────────────────────────────────────────────────────────
# flow_status <flow_id>
flow_status() {
  local flow_id="$1"
  local state_file="${FLOW_DIR}/${flow_id}/state.json"
  [ -f "$state_file" ] || { echo "[ERROR] flow_status: state.json 없음" >&2; return 1; }
  local json head goal status
  json=$(tr -d '\n\r' < "$state_file")
  head="${json%%\"steps\"*}"
  goal=$(_fc_get_field "goal" "$json")
  status=$(printf '%s' "$head" | \
    grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | \
    sed 's/.*:"//;s/"//')
  printf 'flow:   %s\n' "$flow_id"
  printf 'goal:   %s\n' "$goal"
  printf 'status: %s\n' "$status"
  printf '%-30s %-18s %s\n' "step_id" "status" "soul"
  printf '%s\n' "------------------------------------------------------------"
  local line s_id s_status s_soul
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    s_id=$(_fc_get_field "id" "$line")
    s_status=$(_fc_get_field "status" "$line")
    s_soul=$(_fc_get_field "soul" "$line")
    printf '%-30s %-18s %s\n' "$s_id" "$s_status" "${s_soul:-(host)}"
  done <<EOF
$(_fc_steps_lines < "$state_file")
EOF
}

# ── 6. flow_list ──────────────────────────────────────────────────────────────
# flow_list
flow_list() {
  [ -d "$FLOW_DIR" ] || { echo "(플로우 없음)"; return 0; }
  local found=0 sf json head goal status fid
  printf '%-36s %-12s %s\n' "flow_id" "status" "goal"
  printf '%s\n' "------------------------------------------------------------"
  for sf in "${FLOW_DIR}"/*/state.json; do
    [ -f "$sf" ] || continue
    found=1
    json=$(tr -d '\n\r' < "$sf")
    head="${json%%\"steps\"*}"
    goal=$(_fc_get_field "goal" "$json")
    status=$(printf '%s' "$head" | \
      grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | \
      sed 's/.*:"//;s/"//')
    fid=$(basename "$(dirname "$sf")")
    printf '%-36s %-12s %s\n' "$fid" "$status" "$goal"
  done
  [ "$found" -eq 0 ] && echo "(플로우 없음)"
}
