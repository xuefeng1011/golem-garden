#!/usr/bin/env bash
# flow-dag.sh — Flow Engine 상태·DAG 계층
# Usage: source lib/flow-dag.sh
# 의존: lib/flow-contract.sh (flow_validate_steps, flow_parse_steps, _fc_get_field, _fc_get_deps)
# 규칙: jq 금지(grep/sed), 300줄 이내

# ── 내부 유틸 ─────────────────────────────────────────────────────────────

_flow_gen_id() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr 'A-Z' 'a-z'
  else
    printf 'flow_%s_%s' "$(date +%s)" "$$"
  fi
}

FLOW_DIR="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/flows"

# state.json read-modify-write 잠금 — mv 원자성만으로는 동시 writer의
# last-writer-wins 유실을 못 막는다 (리뷰 HIGH-4). mkdir은 POSIX 원자적.
# flock은 Git Bash에 없을 수 있어 미사용. 최대 5초 대기 후 실패.
_flow_lock() {
  local lock_dir="${1}.lock"
  local i=0
  until mkdir "$lock_dir" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -gt 50 ]; then
      echo "[ERROR] flow: 잠금 획득 실패(5s): $lock_dir" >&2
      return 1
    fi
    sleep 0.1
  done
}

_flow_unlock() {
  rmdir "${1}.lock" 2>/dev/null || true
}

# ── 1. flow_create ─────────────────────────────────────────────────────────
# flow_create <goal> <steps_json_file>
# FLOW_DIR/<flow_id>/state.json 생성
flow_create() {
  local goal="$1"
  local steps_file="$2"

  if [ -z "$goal" ] || [ -z "$steps_file" ] || [ ! -f "$steps_file" ]; then
    echo "[ERROR] flow_create: goal과 steps_json_file 필수" >&2
    return 1
  fi

  local steps_json
  steps_json=$(cat "$steps_file")

  # 사전 검증
  if ! printf '%s\n' "$steps_json" | flow_validate_steps; then
    echo "[ERROR] flow_create: steps 검증 실패" >&2
    return 1
  fi

  local flow_id
  flow_id=$(_flow_gen_id)
  local created
  created=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")

  local flow_dir="${FLOW_DIR}/${flow_id}"
  mkdir -p "$flow_dir" || { echo "[ERROR] flow_create: 디렉토리 생성 실패: $flow_dir" >&2; return 1; }

  # 정규화된 step 라인(1객체=1줄)에 "status":"pending" 주입 후 배열 재조립
  # (_fc_steps_lines: flow-contract.sh — 컴팩트/멀티라인 입력 모두 처리)
  local steps_arr=""
  local line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
      *'"status"'*) : ;;
      *) line=$(printf '%s' "$line" | sed 's/}$/,"status":"pending"}/') ;;
    esac
    if [ -z "$steps_arr" ]; then
      steps_arr="$line"
    else
      steps_arr="${steps_arr},${line}"
    fi
  done <<EOF
$(printf '%s\n' "$steps_json" | _fc_steps_lines)
EOF
  steps_arr="[${steps_arr}]"

  # goal JSON 이스케이프 (기본)
  local goal_esc
  goal_esc=$(printf '%s' "$goal" | sed 's/\\/\\\\/g; s/"/\\"/g')

  local json
  json=$(printf '{"flow_id":"%s","goal":"%s","created":"%s","status":"pending","steps":%s}' \
    "$flow_id" "$goal_esc" "$created" "$steps_arr")

  local target="${flow_dir}/state.json"
  local tmp="${target}.tmp.$$"
  printf '%s' "$json" > "$tmp" && mv -f "$tmp" "$target" || {
    echo "[ERROR] flow_create: state.json 쓰기 실패" >&2
    return 1
  }

  # fail-fast: 사이클 등 DAG 위반 플로우는 생성 자체를 거부
  if ! flow_validate "$target"; then
    rm -rf "$flow_dir"
    echo "[ERROR] flow_create: DAG 검증 실패 — 플로우 미생성" >&2
    return 1
  fi

  printf '%s\n' "$flow_id"
}

# ── 2. flow_validate ───────────────────────────────────────────────────────
# flow_validate <state_file>
# flow_validate_steps 재사용 + Kahn 알고리즘 사이클 검출
flow_validate() {
  local state_file="$1"
  [ -f "$state_file" ] || { echo "[ERROR] flow_validate: 파일 없음: $state_file" >&2; return 1; }

  local json
  json=$(cat "$state_file")

  # 구조 검증
  printf '%s\n' "$json" | flow_validate_steps || return 1

  # Kahn 토폴로지 사이클 검출 (순수 bash)
  local parsed
  parsed=$(printf '%s\n' "$json" | flow_parse_steps 2>/dev/null)

  # in_degree 맵: id→count (공백 구분 "id:count" 리스트)
  local id_list=""
  local indegree_list=""

  while IFS=$'\037' read -r id soul task deps; do
    [ -z "$id" ] && continue
    id_list="${id_list} ${id}"
    local cnt=0
    for dep in $deps; do [ -n "$dep" ] && cnt=$((cnt+1)); done
    indegree_list="${indegree_list} ${id}:${cnt}"
  done <<EOF
$parsed
EOF

  # 큐: in_degree=0인 노드
  local queue=""
  for entry in $indegree_list; do
    local nid="${entry%%:*}"; local cnt="${entry##*:}"
    [ "$cnt" -eq 0 ] && queue="${queue} ${nid}"
  done

  local visited=0
  local total
  total=$(printf '%s\n' "$id_list" | tr ' ' '\n' | grep -c .)

  while [ -n "$(printf '%s' "$queue" | tr -d ' ')" ]; do
    # pop first
    local cur
    cur=$(printf '%s' "$queue" | awk '{print $1}')
    queue=$(printf '%s' "$queue" | sed "s/[[:space:]]*${cur}[[:space:]]*//" | sed 's/^ *//')
    visited=$((visited+1))

    # cur를 dep로 가진 노드의 in_degree 감소
    while IFS=$'\037' read -r id soul task deps; do
      [ -z "$id" ] && continue
      local found=0
      for dep in $deps; do [ "$dep" = "$cur" ] && found=1 && break; done
      [ "$found" -eq 0 ] && continue
      # in_degree 감소
      local new_list=""
      for entry in $indegree_list; do
        local nid="${entry%%:*}"; local cnt="${entry##*:}"
        if [ "$nid" = "$id" ]; then
          cnt=$((cnt-1))
          new_list="${new_list} ${nid}:${cnt}"
          [ "$cnt" -eq 0 ] && queue="${queue} ${nid}"
        else
          new_list="${new_list} ${entry}"
        fi
      done
      indegree_list="$new_list"
    done <<EOF
$parsed
EOF
  done

  if [ "$visited" -lt "$total" ]; then
    # 잔여 노드(사이클) stderr 출력
    for entry in $indegree_list; do
      local nid="${entry%%:*}"; local cnt="${entry##*:}"
      [ "$cnt" -gt 0 ] && printf '%s\n' "$nid" >&2
    done
    echo "[ERROR] flow_validate: 사이클 감지됨" >&2
    return 1
  fi

  return 0
}

# ── 3. flow_next_ready ─────────────────────────────────────────────────────
# flow_next_ready <state_file>
# status=pending이고 deps 전부 done인 step id 출력
# approval=true → 'APPROVAL:<id>' 프리픽스
flow_next_ready() {
  local state_file="$1"
  [ -f "$state_file" ] || { echo "[ERROR] flow_next_ready: 파일 없음: $state_file" >&2; return 1; }

  local steps_lines
  steps_lines=$(_fc_steps_lines < "$state_file") || {
    echo "[ERROR] flow_next_ready: steps 배열 파싱 실패" >&2
    return 1
  }

  # 1패스: done step id 수집
  local done_ids=""
  local line s_id s_status
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    s_status=$(_fc_get_field "status" "$line")
    [ "$s_status" = "done" ] || continue
    s_id=$(_fc_get_field "id" "$line")
    [ -n "$s_id" ] && done_ids="${done_ids} ${s_id}"
  done <<EOF
$steps_lines
EOF

  # 2패스: pending(또는 approved — 승인 완료)이고 deps 전부 done인 step 출력
  local s_approval s_deps dep all_done
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    s_status=$(_fc_get_field "status" "$line")
    case "$s_status" in pending|approved) : ;; *) continue ;; esac
    s_id=$(_fc_get_field "id" "$line")
    [ -z "$s_id" ] && continue
    s_approval=$(printf '%s' "$line" | grep -o '"approval"[[:space:]]*:[[:space:]]*[a-z]*' | sed 's/.*://;s/[[:space:]]//g')
    s_deps=$(_fc_get_deps "$line")

    all_done=1
    for dep in $s_deps; do
      [ -z "$dep" ] && continue
      case " ${done_ids} " in
        *" ${dep} "*) : ;;
        *) all_done=0; break ;;
      esac
    done
    [ "$all_done" -eq 1 ] || continue

    if [ "$s_approval" = "true" ] && [ "$s_status" = "pending" ]; then
      printf 'APPROVAL:%s\n' "$s_id"
    else
      printf '%s\n' "$s_id"
    fi
  done <<EOF
$steps_lines
EOF
}

# ── 4. flow_set_step_status ────────────────────────────────────────────────
# flow_set_step_status <state_file> <step_id> <new_status>
# 해당 step의 status 필드만 치환 (1depth 전제, 원자적 쓰기 + 잠금)
flow_set_step_status() {
  local state_file="$1"

  [ -f "$state_file" ] || { echo "[ERROR] flow_set_step_status: 파일 없음: $state_file" >&2; return 1; }
  [ -z "$2" ] || [ -z "$3" ] && { echo "[ERROR] flow_set_step_status: step_id와 new_status 필수" >&2; return 1; }

  _flow_lock "$state_file" || return 1
  local _rc=0
  _flow_set_step_status_locked "$@" || _rc=$?
  _flow_unlock "$state_file"
  return "$_rc"
}

# 잠금 보유 전제의 본체 — 직접 호출 금지
_flow_set_step_status_locked() {
  local state_file="$1"
  local step_id="$2"
  local new_status="$3"

  local json
  json=$(tr -d '\n\r' < "$state_file")

  # 헤더(steps 앞 플로우 레벨 필드) 분리 — 플로우 레벨 status 오염 방지.
  # 계약: steps는 마지막 키 (flow_create가 보장) → 닫는 부분은 ]}
  case "$json" in
    *'"steps"'*) : ;;
    *) echo "[ERROR] flow_set_step_status: steps 배열 없음" >&2; return 1 ;;
  esac
  local head="${json%%\"steps\"*}"

  local steps_lines
  steps_lines=$(printf '%s\n' "$json" | _fc_steps_lines) || {
    echo "[ERROR] flow_set_step_status: steps 파싱 실패" >&2
    return 1
  }

  # 해당 step 라인의 status만 치환
  local rebuilt="" line s_id found=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    s_id=$(_fc_get_field "id" "$line")
    if [ "$s_id" = "$step_id" ]; then
      line=$(printf '%s' "$line" | sed "s/\"status\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"status\":\"${new_status}\"/")
      found=1
    fi
    if [ -z "$rebuilt" ]; then rebuilt="$line"; else rebuilt="${rebuilt},${line}"; fi
  done <<EOF
$steps_lines
EOF

  if [ "$found" -ne 1 ]; then
    echo "[ERROR] flow_set_step_status: step_id '${step_id}' 없음" >&2
    return 1
  fi

  local updated="${head}\"steps\":[${rebuilt}]}"

  local tmp="${state_file}.tmp.$$"
  printf '%s' "$updated" > "$tmp" && mv -f "$tmp" "$state_file" || {
    echo "[ERROR] flow_set_step_status: 파일 쓰기 실패" >&2
    return 1
  }
}

# ── flow_set_step_run_id — step 에 실행 run_id 기록 (단계별 결과 보기용) ──────
# flow_set_step_run_id <state_file> <step_id> <run_id>
# run_id 필드는 step 에 없을 수 있어 add-or-replace. flow_set_step_status 와 동일
# 잠금/재조립 패턴.
flow_set_step_run_id() {
  local state_file="$1"
  [ -f "$state_file" ] || return 1
  [ -z "$2" ] || [ -z "$3" ] && return 1
  _flow_lock "$state_file" || return 1
  local _rc=0
  _flow_set_step_run_id_locked "$@" || _rc=$?
  _flow_unlock "$state_file"
  return "$_rc"
}

_flow_set_step_run_id_locked() {
  local state_file="$1" step_id="$2" run_id="$3"
  local json head steps_lines rebuilt="" line s_id found=0
  json=$(tr -d '\n\r' < "$state_file")
  case "$json" in *'"steps"'*) : ;; *) return 1 ;; esac
  head="${json%%\"steps\"*}"
  steps_lines=$(printf '%s\n' "$json" | _fc_steps_lines) || return 1
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    s_id=$(_fc_get_field "id" "$line")
    if [ "$s_id" = "$step_id" ]; then
      # 기존 run_id(선행 콤마 포함) 제거 후 닫는 } 앞에 삽입 (add-or-replace)
      line=$(printf '%s' "$line" | sed -E 's/,?"run_id":"[^"]*"//')
      line=$(printf '%s' "$line" | sed "s/}\$/,\"run_id\":\"${run_id}\"}/")
      found=1
    fi
    if [ -z "$rebuilt" ]; then rebuilt="$line"; else rebuilt="${rebuilt},${line}"; fi
  done <<EOF
$steps_lines
EOF
  [ "$found" -eq 1 ] || return 1
  local updated="${head}\"steps\":[${rebuilt}]}"
  local tmp="${state_file}.tmp.$$"
  printf '%s' "$updated" > "$tmp" && mv -f "$tmp" "$state_file"
}

# ── flow_set_step_output — step 에 산출 텍스트 기록 (단계 간 데이터 전달) ──────
# flow_set_step_output <state_file> <step_id> <text>
# 값은 캡(4000자) + JSON 이스케이프. add-or-replace, 잠금/재조립 패턴 동일.
_FLOW_OUTPUT_CAP=4000

# 자기완결 JSON 문자열 이스케이프 (\\ " \t \b \f \r 줄바꿈→\n, 기타 제어문자 제거)
# 에이전트 출력에 제어바이트(BEL·ANSI 등)가 섞여도 JSON 이 깨지지 않도록 한다.
_flow_json_escape() {
  printf '%s' "$1" \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' \
          -e "s/$(printf '\b')/\\\\b/g" -e "s/$(printf '\f')/\\\\f/g" \
          -e 's/\r//g' \
    | tr -d '\000-\010\013\016-\037' \
    | awk '{if(NR>1) printf "\\n"; printf "%s",$0}'
}

flow_set_step_output() {
  local state_file="$1"
  [ -f "$state_file" ] || return 1
  [ -z "$2" ] && return 1
  _flow_lock "$state_file" || return 1
  local _rc=0
  _flow_set_step_output_locked "$@" || _rc=$?
  _flow_unlock "$state_file"
  return "$_rc"
}

_flow_set_step_output_locked() {
  local state_file="$1" step_id="$2" text="$3"
  # 캡(이스케이프 전) 후 이스케이프
  text="${text:0:$_FLOW_OUTPUT_CAP}"
  local esc
  esc=$(_flow_json_escape "$text")
  local json head steps_lines rebuilt="" line s_id found=0
  json=$(tr -d '\n\r' < "$state_file")
  case "$json" in *'"steps"'*) : ;; *) return 1 ;; esac
  head="${json%%\"steps\"*}"
  steps_lines=$(printf '%s\n' "$json" | _fc_steps_lines) || return 1
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    s_id=$(_fc_get_field "id" "$line")
    if [ "$s_id" = "$step_id" ]; then
      # 기존 output(선행 콤마 포함) 제거
      line=$(printf '%s' "$line" | sed -E 's/,?"output":"([^"\\]|\\.)*"//')
      # 닫는 } 앞에 삽입 — bash 문자열 연산(awk -v/sed 는 esc의 \n·\" 를
      # 재해석/충돌시킴). esc 는 이미 JSON 이스케이프된 리터럴.
      local _brace='}'
      line="${line%$_brace},\"output\":\"${esc}\"}"
      found=1
    fi
    if [ -z "$rebuilt" ]; then rebuilt="$line"; else rebuilt="${rebuilt},${line}"; fi
  done <<EOF
$steps_lines
EOF
  [ "$found" -eq 1 ] || return 1
  local updated="${head}\"steps\":[${rebuilt}]}"
  local tmp="${state_file}.tmp.$$"
  printf '%s' "$updated" > "$tmp" && mv -f "$tmp" "$state_file"
}

# ── flow_step_output — step 의 저장된 output 텍스트 조회 (치환용) ──────────────
# flow_step_output <state_file> <step_id> → stdout (이스케이프된 원본; \n 유지)
flow_step_output() {
  local state_file="$1" step_id="$2"
  [ -f "$state_file" ] || return 1
  local line
  line=$(_fc_steps_lines < "$state_file" | grep -F "\"id\":\"${step_id}\"")
  [ -z "$line" ] && return 1
  # "output":"..." 값 추출 (이스케이프된 \" 포함) — grep -o + 앞뒤 제거
  printf '%s' "$line" \
    | grep -oE '"output":"([^"\\]|\\.)*"' \
    | sed -E 's/^"output":"//; s/"$//'
}
