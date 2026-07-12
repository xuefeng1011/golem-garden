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
# JSON 이스케이프된 output 을 실제 텍스트로 복원 (\n→줄바꿈, \t→탭, \"→", \\→\)
# 순서 주의(MED-7): \\(더블 백슬래시)를 센티널(\001)로 먼저 빼내고 나서 \n/\t/\"
# 를 복원하고 마지막에 센티널을 \ 로 되돌린다. 반대 순서(\" → \n → \\)면 리터럴
# "\n"(역슬래시+n 두 글자, 실제 개행이 아님)이 이스케이프 단계에서 역슬래시가
# 배가돼 "\\n"(석 자)로 저장돼 있어도 \n 치환이 뒤쪽 두 글자(역슬래시+n)를 먼저
# 개행으로 오매칭해 "역슬래시+실제개행"으로 변질된다. \001 은 저장측
# (_flow_json_escape, lib/flow-dag.sh)이 tr -d '\000-\010...' 로 제어문자를
# 제거하므로 저장된 output 에 리터럴로 존재할 수 없어 센티널 충돌이 불가능하다.
# gap: \b(backspace)/\f(formfeed) 는 escape 측 대칭이 없어 여기서 복원하지 않는다.
_flow_unescape() {
  local _s
  _s=$(printf '\001')
  printf '%s' "$1" | sed \
    -e 's/\\\\/'"${_s}"'/g' \
    -e 's/\\n/\
/g' \
    -e 's/\\t/'"$(printf '\t')"'/g' \
    -e 's/\\"/"/g' \
    -e 's/'"${_s}"'/\\/g'
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

# ── 병렬 배치 실행 (GOLEM_FLOW_PARALLEL) ─────────────────────────────────────
# 노브: GOLEM_FLOW_PARALLEL — 정수 최대 동시 수. 미설정/1/비숫자 → 직렬(기존
# 동작 무변화, 코드 경로 분기). 2 이상 → 웨이브 배치 실행. 상한 8 클램프.
_flow_parallel_n() {
  local raw="${GOLEM_FLOW_PARALLEL:-1}"
  case "$raw" in
    ''|*[!0-9]*) echo 1; return ;;
  esac
  [ "$raw" -lt 1 ] && raw=1
  [ "$raw" -gt 8 ] && raw=8
  echo "$raw"
}

# _flow_step_field <state_file> <step_id> <field> — 배치 분류용 단일 필드 조회
# (flow_step_run 과 동일 grep -F 패턴 — step_id 의 정규식 메타문자 오매칭 차단)
_flow_step_field() {
  local state_file="$1" step_id="$2" field="$3"
  local line
  line=$(_fc_steps_lines < "$state_file" | grep -F "\"id\":\"${step_id}\"")
  [ -z "$line" ] && return 1
  _fc_get_field "$field" "$line"
}

# _flow_soul_rank <soul_name> — SOUL 파일의 rank 필드 조회(프로젝트 오버라이드
# 우선, _resolve_soul_file/soul_get_field — lib/soul-parser.sh, agent-runner.sh
# 경유 이미 source 됨). 파일 미발견 시 빈 문자열.
_flow_soul_rank() {
  local soul_name="$1"
  [ -z "$soul_name" ] && return 0
  local soul_file
  soul_file=$(_resolve_soul_file "$soul_name" 2>/dev/null)
  [ -z "$soul_file" ] && return 0
  soul_get_field "$soul_file" "rank"
}

# _flow_is_low_rank <soul_name> — novice/junior면 0(true, 병렬 배치에서 제외).
# GOLEM_FLOW_PARALLEL_RANK_GATE=0 이면 게이트 해제(항상 1/false) — 세션 포인터
# --resume 동시 재개 + growth-log 기록 경합을 피하려는 기본 안전장치.
_flow_is_low_rank() {
  local soul_name="$1"
  [ "${GOLEM_FLOW_PARALLEL_RANK_GATE:-1}" = "0" ] && return 1
  case "$(_flow_soul_rank "$soul_name")" in
    novice|junior) return 0 ;;
    *) return 1 ;;
  esac
}

# _flow_build_batches <state_file> <cap> <id...> — stdout: 배치당 1줄(공백
# 구분 id 목록). 배치당 동일 soul 최대 1회 + 배치 크기 cap 이하가 되도록
# first-fit 배정(입력 순서 보존 → 론치 순서 = 재생 순서). bash 3.2 대응
# (연관배열 금지) — 인덱스 배열 병렬 페어(batch_ids/batch_souls)로 추적.
_flow_build_batches() {
  local state_file="$1" cap="$2"
  shift 2
  local -a cand=("$@")
  local -a batch_ids=() batch_souls=()
  local id soul bi cnt placed

  for id in "${cand[@]}"; do
    soul=$(_flow_step_field "$state_file" "$id" "soul")
    placed=0
    bi=0
    while [ "$bi" -lt "${#batch_ids[@]}" ]; do
      case " ${batch_souls[$bi]} " in
        *" ${soul} "*) : ;;
        *)
          cnt=$(printf '%s\n' "${batch_ids[$bi]}" | wc -w)
          if [ "$cnt" -lt "$cap" ]; then
            batch_ids[$bi]="${batch_ids[$bi]} ${id}"
            batch_souls[$bi]="${batch_souls[$bi]} ${soul}"
            placed=1
            break
          fi
          ;;
      esac
      bi=$((bi + 1))
    done
    if [ "$placed" -eq 0 ]; then
      batch_ids+=("$id")
      batch_souls+=("$soul")
    fi
  done

  for bi in "${!batch_ids[@]}"; do
    printf '%s\n' "${batch_ids[$bi]}" | sed 's/^ *//'
  done
}

# _flow_run_wave <flow_id> <state_file> <step_id...> — 배치를 병렬 실행.
# 각 step 을 백그라운드 서브셸로 소환하고 stdout/stderr/rc 를 wave_dir 에
# 캡처, 전원 종료(wait) 후 론치 순서대로 재생 — 출력 스트림이 직렬 실행과
# 동형이 되어 마커 파서(web/client) 는 무변경으로 병렬/직렬을 구분하지 못한다.
# 실패해도 형제를 죽이지 않는다(전원 완주 후 판정) — on_fail 시맨틱은
# flow_step_run 내부에서 이미 처리되므로 여기서는 rc 집계만 한다.
# 주의: 백그라운드 서브셸 안에서 $$ 는 부모(flow_run) pid 그대로다(bash 3.2 —
# BASHPID 는 4.0+ 전용이라 사용 금지). 그래서 형제 서브셸이 동시에 잡는
# per-op 잠금(_flow_lock, lib/flow-dag.sh)의 holder pid 는 전부 같은 값을
# 기록하고, 대기 타임아웃 후 stale 판정(kill -0)도 이 살아있는 공유 pid를
# 보게 되어 항상 "살아있음"으로 나온다 — 형제 락을 죽은 것으로 오판해
# 강탈하는 사고가 구조적으로 불가능하다.
_flow_run_wave() {
  local flow_id="$1" state_file="$2"
  shift 2
  local -a ids=("$@")
  [ "${#ids[@]}" -eq 0 ] && return 0

  local flow_dir="${FLOW_DIR}/${flow_id}"
  # wave.$$ 는 PID 로 네임스페이스 — 동일 PID 가 재사용되며 남긴 이전 잔해를
  # 새 웨이브가 자기 것으로 오인하지 않도록 먼저 비운다. mkdir 실패는(디스크
  # full/권한 등) 즉시 에러 반환해 이후 out/err/rc 캡처가 존재하지 않는
  # 디렉터리에 조용히 쓰기 실패하는 것을 막는다.
  local wave_dir="${flow_dir}/wave.$$"
  rm -rf "$wave_dir" 2>/dev/null
  mkdir -p "$wave_dir" || { echo "[ERROR] _flow_run_wave: wave_dir 생성 실패" >&2; return 1; }

  local -a pids=()
  local sid
  for sid in "${ids[@]}"; do
    ( flow_step_run "$flow_id" "$sid" >"${wave_dir}/${sid}.out" 2>"${wave_dir}/${sid}.err"
      echo $? >"${wave_dir}/${sid}.rc" ) &
    pids+=("$!")
  done

  local p
  for p in "${pids[@]}"; do
    wait "$p" || true
  done

  local rc_all=0 rc
  for sid in "${ids[@]}"; do
    cat "${wave_dir}/${sid}.out" 2>/dev/null
    cat "${wave_dir}/${sid}.err" 2>/dev/null >&2
    if [ -f "${wave_dir}/${sid}.rc" ]; then
      rc=$(cat "${wave_dir}/${sid}.rc" 2>/dev/null)
    else
      rc=1
    fi
    case "$rc" in ''|*[!0-9]*) rc=1 ;; esac
    [ "$rc" -ne 0 ] && rc_all=1
  done

  rm -rf "$wave_dir"
  return "$rc_all"
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
  retry=${retry:-1}; on_fail=${on_fail:-abort}; type=${type:-agent}

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

  local flow_dir="${FLOW_DIR}/${flow_id}"
  local _errf="${flow_dir}/.step-stderr.$$"
  local attempt=0 rc=0 _out=""
  while true; do
    # 출력 캡처 후 재출력 — run_id 추출(단계별 결과 보기) + SSE 로그 보존.
    # if 분기로 호출 — `cmd; rc=$?`는 set -e(bats/forge.sh) 환경에서 즉사한다
    # stderr는 flow 디렉토리 내 임시 파일로 캡처(재시도 시 마지막 시도로 덮어씀,
    # /tmp 미사용 — LOW-5) — 실패 사유가 stdout에 없을 때 폴백 소스로 쓴다.
    if _out=$(agent_run "$soul" "$task" 2>"$_errf"); then rc=0; else rc=$?; fi
    printf '%s\n' "$_out"
    [ "$rc" -eq 0 ] && break
    attempt=$((attempt + 1))
    if [ "$attempt" -gt "$retry" ]; then break; fi
    # 재시도 전 지수 백오프 (레이트리밋 완화)
    local _bk; _bk=$(_flow_retry_backoff_secs "$attempt")
    [ "${_bk:-0}" -gt 0 ] 2>/dev/null && sleep "$_bk"
  done

  local _stderr_tail=""
  [ "$rc" -ne 0 ] && [ -f "$_errf" ] && _stderr_tail=$(tail -c 300 "$_errf" 2>/dev/null)
  rm -f "$_errf"

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
  if [ -z "${_reason// /}" ]; then
    if [ -n "${_stderr_tail// /}" ]; then
      _reason=$(_flow_marker_snip "$_stderr_tail" 120)
    else
      _reason="agent_run rc=${rc}"
    fi
  fi
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
    if ! flow_set_step_status "$state_file" "$goto_target" "pending"; then
      echo "[FLOW] goto 실패: target '${goto_target}' 상태 변경 불가 — abort 처리" >&2
      _flow_set_flow_status "$state_file" "failed"
      return 1
    fi
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

# ── 하류 skip 전파 + 종결 status 확정 (MED-6) ────────────────────────────────
# flow_reject 는 대상 step 만 skipped 로 바꾸고 끝나면 하류 step 이 deps 미충족
# 상태로 영원히 pending 고착되고 flow status 도 갱신되지 않는 limbo 에 빠진다.
# _flow_cascade_skip 로 하류를 고정점까지 skip 전파하고, flow_run 과 동일한
# _flow_finalize_status 로 최종 status 를 확정한다.

# _flow_cascade_skip <state_file>
# status 가 pending/waiting_approval/approved 인 step 중 deps 에 skipped 인 id 가
# 하나라도 있으면 skipped 로 전이. 변화가 없을 때까지 반복(스텝 수로 상한).
# 멤버십 검사(" ${list} " 패턴)는 flow_next_ready(lib/flow-dag.sh)의 done_ids
# 관용구를 그대로 재사용. 새로 skipped 로 전이된 step id 를 한 줄씩 stdout 출력
# (flow_reject 가 "하류 skip: ..." 메시지 조립에 사용).
_flow_cascade_skip() {
  local state_file="$1"
  local total
  total=$(_fc_steps_lines < "$state_file" | grep -c '"id"') || total=0
  local max_iter=$(( total + 1 )); [ "$max_iter" -lt 1 ] && max_iter=1

  local iter=0 changed=1
  while [ "$changed" -eq 1 ] && [ "$iter" -lt "$max_iter" ]; do
    iter=$((iter + 1))
    changed=0

    local steps_lines line s_id s_status skipped_ids=""
    steps_lines=$(_fc_steps_lines < "$state_file")
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      s_status=$(_fc_get_field "status" "$line")
      [ "$s_status" = "skipped" ] || continue
      s_id=$(_fc_get_field "id" "$line")
      [ -n "$s_id" ] && skipped_ids="${skipped_ids} ${s_id}"
    done <<EOF
$steps_lines
EOF

    local s_deps dep hit
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      s_status=$(_fc_get_field "status" "$line")
      case "$s_status" in pending|waiting_approval|approved) : ;; *) continue ;; esac
      s_id=$(_fc_get_field "id" "$line")
      [ -z "$s_id" ] && continue
      s_deps=$(_fc_get_deps "$line")

      hit=0
      for dep in $s_deps; do
        [ -z "$dep" ] && continue
        case " ${skipped_ids} " in
          *" ${dep} "*) hit=1; break ;;
        esac
      done
      if [ "$hit" -eq 1 ]; then
        flow_set_step_status "$state_file" "$s_id" "skipped"
        printf '%s\n' "$s_id"
        changed=1
      fi
    done <<EOF
$steps_lines
EOF
  done
}

# _flow_finalize_status <state_file>
# 미종결(pending|waiting_approval|approved|running) step 이 남아있으면 아무것도
#하지 않는다(호출자가 판단할 몫). 0개면: failed step 존재 시 flow status
# "failed", 아니면 "completed". flow_run 마감 로직과 flow_reject 양쪽이 공유 —
# 신규 status 값 도입 없음(클라 union: pending|running|paused|completed|failed).
_flow_finalize_status() {
  local state_file="$1"
  local has_unfinished has_failed
  has_unfinished=$(_fc_steps_lines < "$state_file" | \
    grep -cE '"status":"(pending|waiting_approval|approved|running)"' 2>/dev/null) || has_unfinished=0
  [ "${has_unfinished:-0}" -gt 0 ] && return 0

  has_failed=$(_fc_steps_lines < "$state_file" | \
    grep -c '"status":"failed"' 2>/dev/null) || has_failed=0
  if [ "${has_failed:-0}" -gt 0 ]; then
    _flow_set_flow_status "$state_file" "failed"
  else
    _flow_set_flow_status "$state_file" "completed"
  fi
}

# ── 3. flow_reject ────────────────────────────────────────────────────────────
# flow_reject <flow_id> <step_id>
flow_reject() {
  local flow_id="$1" step_id="$2"
  local state_file="${FLOW_DIR}/${flow_id}/state.json"
  [ -f "$state_file" ] || { echo "[ERROR] flow_reject: state.json 없음" >&2; return 1; }
  flow_set_step_status "$state_file" "$step_id" "skipped" || return 1

  local cascaded_ids cascaded_list
  cascaded_ids=$(_flow_cascade_skip "$state_file")
  _flow_finalize_status "$state_file"

  cascaded_list=$(printf '%s' "$cascaded_ids" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
  printf '[FLOW] 거부: %s — 하류 skip: %s\n' "$step_id" "${cascaded_list:-(없음)}"
}

# ── 4. flow_run ───────────────────────────────────────────────────────────────
# flow 단위 실행 락 (HIGH-1) — 동시 러너가 같은 flow 를 실행하면 서로의 running
# step 을 리셋하고 이중 에이전트 소환이 발생한다. 대기 루프 없이 즉시 실패시켜
# 상위(mission 루프 등)가 재시도 여부를 결정하게 한다. stale 회수 정책은
# flow-dag.sh _flow_lock 을 미러.
_flow_run_lock() {
  local flow_dir="$1"
  local lock_dir="${flow_dir}/run.lock"

  if mkdir "$lock_dir" 2>/dev/null; then
    printf '%s' "$$" > "${lock_dir}/pid" 2>/dev/null || true
    return 0
  fi

  local _holder
  _holder=$(cat "${lock_dir}/pid" 2>/dev/null)
  if [ -n "$_holder" ] && kill -0 "$_holder" 2>/dev/null; then
    echo "[ERROR] flow_run: 이미 실행 중인 flow (holder pid=${_holder})" >&2
    return 1
  fi

  echo "[WARN] flow_run: stale run.lock 회수 (holder=${_holder:-none}): $lock_dir" >&2
  rm -rf "$lock_dir" 2>/dev/null
  if mkdir "$lock_dir" 2>/dev/null; then
    printf '%s' "$$" > "${lock_dir}/pid" 2>/dev/null || true
    return 0
  fi
  echo "[ERROR] flow_run: 잠금 획득 실패: $lock_dir" >&2
  return 1
}

_flow_run_unlock() {
  rm -rf "${1}/run.lock" 2>/dev/null || true
}

# flow_run <flow_id> — 잠금 획득 후 본체(_flow_run_locked) 실행, 모든 경로에서 해제 보장
flow_run() {
  local flow_id="$1"
  local state_file="${FLOW_DIR}/${flow_id}/state.json"
  [ -f "$state_file" ] || { echo "[ERROR] flow_run: state.json 없음" >&2; return 1; }

  # 병렬 웨이브(GOLEM_FLOW_PARALLEL>=2) 동시 종료 시 state.json per-op 잠금
  # 경합이 늘어나므로, 명시적 override 가 없으면 대기 상한을 상향한다.
  if [ "$(_flow_parallel_n)" -ge 2 ] && [ -z "${GOLEM_FLOW_LOCK_WAIT_ITERS:-}" ]; then
    export GOLEM_FLOW_LOCK_WAIT_ITERS=150
  fi

  local flow_dir="${FLOW_DIR}/${flow_id}"
  _flow_run_lock "$flow_dir" || return 1
  local _rc=0
  _flow_run_locked "$flow_id" || _rc=$?
  _flow_run_unlock "$flow_dir"
  return "$_rc"
}

# 잠금 보유 전제의 본체 — 직접 호출 금지
_flow_run_locked() {
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
  local has_unfinished
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
      # completed로 오기록하던 회귀 방지 (리뷰 HIGH-2). 종결 판정 자체는
      # flow_reject 와 공유하는 _flow_finalize_status 가 담당(MED-6).
      has_unfinished=$(_fc_steps_lines < "$state_file" | \
        grep -cE '"status":"(pending|waiting_approval|approved|running)"' 2>/dev/null) || has_unfinished=0
      [ "${has_unfinished:-0}" -gt 0 ] && break
      _flow_finalize_status "$state_file"
      break
    fi
    local _parallel_n
    _parallel_n=$(_flow_parallel_n)

    if [ "$_parallel_n" -le 1 ]; then
      # 직렬 경로 (GOLEM_FLOW_PARALLEL 미설정/1/비숫자) — 기존 동작 그대로
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
    else
      # 병렬 경로 — APPROVAL/host/input 스텝은 부모에서 즉시 처리(마커 라이브
      # 유지), agent 스텝(soul 존재 + type=agent)만 병렬 배치 후보로 수집
      local -a _agent_candidates=()
      local _c_soul _c_type
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
            _c_soul=$(_flow_step_field "$state_file" "$step_id" "soul")
            _c_type=$(_flow_step_field "$state_file" "$step_id" "type")
            _c_type=${_c_type:-agent}
            if [ -z "$_c_soul" ] || [ "$_c_type" != "agent" ]; then
              if ! flow_step_run "$flow_id" "$step_id"; then
                got_abort=1
                break
              fi
            else
              _agent_candidates+=("$step_id")
            fi ;;
        esac
      done <<EOF
$ready_lines
EOF

      if [ "$got_abort" -eq 0 ] && [ "${#_agent_candidates[@]}" -gt 0 ]; then
        local -a _par_ids=() _tail_ids=()
        local _cid _csoul
        for _cid in "${_agent_candidates[@]}"; do
          _csoul=$(_flow_step_field "$state_file" "$_cid" "soul")
          if _flow_is_low_rank "$_csoul"; then
            _tail_ids+=("$_cid")
          else
            _par_ids+=("$_cid")
          fi
        done

        if [ "${#_par_ids[@]}" -gt 0 ]; then
          local _batches_out _batch_line
          local -a _batch_ids
          _batches_out=$(_flow_build_batches "$state_file" "$_parallel_n" "${_par_ids[@]}")
          while IFS= read -r _batch_line; do
            [ -z "$_batch_line" ] && continue
            [ "$got_abort" -eq 1 ] && break
            _batch_ids=()
            read -r -a _batch_ids <<< "$_batch_line"
            printf '[FLOW] 병렬 배치 실행: %s (N=%s)\n' "$_batch_line" "${#_batch_ids[@]}"
            if ! _flow_run_wave "$flow_id" "$state_file" "${_batch_ids[@]}"; then
              got_abort=1
            fi
          done <<BATCH_EOF
$_batches_out
BATCH_EOF
        fi

        # rank 게이트로 미룬 novice/junior 스텝 — 배치 완료 후 직렬 꼬리 실행
        if [ "$got_abort" -eq 0 ] && [ "${#_tail_ids[@]}" -gt 0 ]; then
          for _cid in "${_tail_ids[@]}"; do
            if ! flow_step_run "$flow_id" "$_cid"; then
              got_abort=1
              break
            fi
          done
        fi
      fi
    fi

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
