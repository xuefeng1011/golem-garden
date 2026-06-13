#!/bin/bash
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

  local soul task retry on_fail
  soul=$(_fc_get_field "soul" "$step_line")
  task=$(_fc_get_field "task" "$step_line")
  retry=$(_fc_get_field "retry" "$step_line")
  on_fail=$(_fc_get_field "on_fail" "$step_line")
  retry=${retry:-0}; on_fail=${on_fail:-abort}

  flow_set_step_status "$state_file" "$step_id" "running"

  if [ -z "$soul" ]; then
    printf 'HOST:%s\n' "$task"
    flow_set_step_status "$state_file" "$step_id" "done"
    return 0
  fi

  local attempt=0 rc=0
  while true; do
    # if 분기로 호출 — `cmd; rc=$?`는 set -e(bats/forge.sh) 환경에서 즉사한다
    if agent_run "$soul" "$task" 2>/dev/null; then rc=0; else rc=$?; fi
    [ "$rc" -eq 0 ] && break
    attempt=$((attempt + 1))
    if [ "$attempt" -gt "$retry" ]; then break; fi
  done

  if [ "$rc" -eq 0 ]; then
    flow_set_step_status "$state_file" "$step_id" "done"
    return 0
  fi

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
# flow_run <flow_id> [session_id]
flow_run() {
  local flow_id="$1" session_id="${2:-}"
  local state_file="${FLOW_DIR}/${flow_id}/state.json"
  [ -f "$state_file" ] || { echo "[ERROR] flow_run: state.json 없음" >&2; return 1; }
  local total_steps ready_lines got_approval got_abort step_id prefix
  local has_unfinished has_failed
  total_steps=$(_fc_steps_lines < "$state_file" | grep -c '"id"')
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
