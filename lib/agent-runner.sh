#!/bin/bash
# agent-runner.sh — OMC 비의존 SOUL 에이전트 실행기 (engine-native)
# Usage: source lib/agent-runner.sh && agent_run ryn "REST API 구현"
#
# 웹 게이트웨이(session_manager.py)와 동일한 패턴으로 `claude` CLI를 직접 호출하여
# SOUL 에이전트를 소환한다. OMC의 Agent(subagent_type=...) 메커니즘이나
# soul_to_omc_agent 매핑에 의존하지 않는다.
#
# 게이트웨이 호출 형태(미러):
#   claude --print --output-format=stream-json --verbose \
#     ( --session-id <uuid> | --resume <uuid> ) \
#     --append-system-prompt <SYSTEM_PROMPT> \
#     --model <model> --allowedTools <csv> \
#     -- <USER_INPUT>

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# GOLEM_DIR 정규화 — forge.sh 로직 미러.
# 단독 source(forge.sh 경유 아님) 시 GOLEM_DIR 이 비었거나 .golem 이 아닌
# 경로(루트 등)로 잘못 설정돼 있을 수 있어, 세션 마커 write/check 가 어긋난다.
# 항상 실제 .golem/ 을 가리키도록 보정한다.
case "${GOLEM_DIR:-}" in
  */.golem) : ;;  # 이미 .golem 으로 끝나면 그대로 신뢰
  *)
    if [ -n "${GOLEM_PROJECT:-}" ]; then
      GOLEM_DIR="${GOLEM_PROJECT}/.golem"
    elif [ -d "$(pwd)/.golem" ]; then
      GOLEM_DIR="$(pwd)/.golem"
    else
      GOLEM_DIR="${GOLEM_ROOT}/.golem"
    fi
    ;;
esac

source "${GOLEM_ROOT}/lib/soul-parser.sh"
source "${GOLEM_ROOT}/lib/prompt-builder.sh"
source "${GOLEM_ROOT}/lib/growth-log.sh"

# 게이트웨이 CLAUDE_ARGS_BASE 미러 (config.py)
_AGENT_CLAUDE_BASE=(--print --output-format=stream-json --verbose)

# ─────────────────────────────────────────────────────────
# RUNAWAY PROTECTION — 폭주 방지 가드 (게이트웨이 MAX_RUN_SECONDS 미러)
# ─────────────────────────────────────────────────────────
# 게이트웨이(config.py)는 MAX_RUN_SECONDS=300 으로 claude 자식 프로세스에
# 벽시계 타임아웃을 건다. 디커플된 bash 경로(agent_run)에는 이 가드가 없어
# 행 걸리거나 루프 도는 claude 자식이 미션을 무한정 막거나 비용을 무한 소진할 수
# 있었다(크로스 리뷰 지적). 아래 가드로 이를 미러한다.
#
# AGENT_MAX_SECONDS  — claude 소환 벽시계 타임아웃(초). 기본 300(게이트웨이와 동일).
# AGENT_MAX_COST_USD — 단일 run 비용 상한(USD). 빈 값=비활성(기본). 초과 시 stderr 경고
#                      (사후 트립와이어 — 가시성 가드일 뿐 사전 차단 아님).
AGENT_MAX_SECONDS="${AGENT_MAX_SECONDS:-300}"
AGENT_MAX_COST_USD="${AGENT_MAX_COST_USD:-}"

# timeout 명령 프리픽스 배열을 stdout 으로 출력한다.
# - GNU coreutils `timeout` (리눅스/Git-bash) 또는 `gtimeout` (macОS coreutils) 탐지.
# - 둘 다 없으면 빈 출력 → 호출부가 무가드로 폴백(한 번 경고).
# 사용: read -r -a _pfx < <(_agent_timeout_cmd) ; "${_pfx[@]}" claude ...
# 단위 테스트 가능: AGENT_MAX_SECONDS=5 _agent_timeout_cmd → "timeout 5"
_agent_timeout_cmd() {
  local secs="${AGENT_MAX_SECONDS:-300}"
  # 정수 검증 — 비정상 값이면 기본 300
  printf '%s' "$secs" | grep -qE '^[0-9]+$' || secs=300
  if command -v timeout >/dev/null 2>&1; then
    printf '%s %s\n' "timeout" "$secs"
  elif command -v gtimeout >/dev/null 2>&1; then
    printf '%s %s\n' "gtimeout" "$secs"
  else
    printf '\n'  # 빈 출력 — 가드 없음
  fi
}

# ─────────────────────────────────────────────────────────
# 헬퍼
# ─────────────────────────────────────────────────────────

# 이식성 있는 UUID 생성 (게이트웨이 uuid.uuid4 대체)
# 우선순위: /proc → python → /dev/urandom 폴백
_gen_uuid() {
  if [ -r /proc/sys/kernel/random/uuid ]; then
    cat /proc/sys/kernel/random/uuid
    return
  fi
  local py uuid_out
  py=$(command -v python3 || command -v python)
  if [ -n "$py" ]; then
    # Windows WindowsApps python3 스텁은 stderr 로 "Python" 배너를 흘리므로 2>/dev/null
    # stdout(UUID)만 캡처해 비어있지 않을 때만 사용 (스텁/미설치 시 빈 출력 → 폴백)
    uuid_out=$("$py" -c 'import uuid;print(uuid.uuid4())' 2>/dev/null)
    if [ -n "$uuid_out" ]; then
      printf '%s\n' "$uuid_out"
      return
    fi
  fi
  # /dev/urandom 폴백 — RFC 4122 형태로 조립
  if [ -r /dev/urandom ]; then
    local hex
    hex=$(od -An -tx1 -N16 /dev/urandom 2>/dev/null | tr -d ' \n')
    if [ ${#hex} -eq 32 ]; then
      printf '%s-%s-4%s-%s-%s\n' \
        "${hex:0:8}" "${hex:8:4}" "${hex:13:3}" \
        "8${hex:17:3}" "${hex:20:12}"
      return
    fi
  fi
  # 최후 폴백 — 시각 + PID (충돌 가능성 낮음, 디버그 전용)
  printf '%s-%s-%s\n' "$(date +%s)" "$$" "$RANDOM"
}

# SOUL.model → claude --model 값 매핑
# opus/sonnet/haiku 별칭은 그대로, 전체 모델 id(claude-...)는 통과
_map_model() {
  local model="$1"
  case "$model" in
    opus|sonnet|haiku)  echo "$model" ;;
    claude-*)           echo "$model" ;;   # 전체 id 통과
    "")                 echo "sonnet" ;;   # 기본값
    *)                  echo "$model" ;;   # 알 수 없으면 통과 (CLI가 검증)
  esac
}

# SOUL_TOOLS("Read, Edit, Write") → claude --allowedTools CSV("Read,Edit,Write")
# 공백 제거만 수행 (frontmatter는 ", " 구분, CLI는 "," 구분)
_tools_csv() {
  printf '%s' "$1" | tr -d ' '
}

# stream-json 한 줄에서 키 값 추출 (jq 미사용 — 프로젝트 컨벤션)
# _json_field <json_line> <key> → 값 (숫자/문자열)
_json_num_field() {
  local line="$1"
  local key="$2"
  printf '%s' "$line" | grep -o "\"${key}\":[0-9]*" | head -1 | cut -d: -f2
}

# ─────────────────────────────────────────────────────────
# stream-json 결과 파싱
# ─────────────────────────────────────────────────────────
# claude --output-format=stream-json 출력에서:
#   - type=result 라인 → is_error, duration_ms, usage(input/output/cache tokens)
#   - type=assistant text 블록 → 최종 어시스턴트 텍스트 누적
# events.py parse_stream_event 의 bash 미러. jq 미사용.
#
# stdin 으로 stream-json 을 받아 다음을 전역에 설정:
#   _AR_RESULT_TEXT, _AR_IS_ERROR, _AR_DURATION_MS,
#   _AR_TOKENS_IN, _AR_TOKENS_OUT, _AR_TOKENS_CACHE
_parse_stream() {
  _AR_RESULT_TEXT=""
  _AR_IS_ERROR=0
  _AR_DURATION_MS=0
  _AR_TOKENS_IN=0
  _AR_TOKENS_OUT=0
  _AR_TOKENS_CACHE=0
  local result_field=""

  while IFS= read -r line; do
    [ -z "$line" ] && continue

    # result 라인 (terminal) — usage + 에러 + duration
    if printf '%s' "$line" | grep -q '"type":"result"'; then
      _AR_DURATION_MS=$(_json_num_field "$line" "duration_ms")
      _AR_DURATION_MS=${_AR_DURATION_MS:-0}
      if printf '%s' "$line" | grep -q '"is_error":true'; then
        _AR_IS_ERROR=1
      fi
      # usage 객체 내 토큰 카운트 (input_tokens, output_tokens,
      # cache_read_input_tokens, cache_creation_input_tokens)
      local in_t out_t cr_t cc_t
      in_t=$(_json_num_field "$line" "input_tokens")
      out_t=$(_json_num_field "$line" "output_tokens")
      cr_t=$(_json_num_field "$line" "cache_read_input_tokens")
      cc_t=$(_json_num_field "$line" "cache_creation_input_tokens")
      _AR_TOKENS_IN=${in_t:-0}
      _AR_TOKENS_OUT=${out_t:-0}
      _AR_TOKENS_CACHE=$(( ${cr_t:-0} + ${cc_t:-0} ))
      # result 라인은 보통 "result" 키에 최종 텍스트를 담음 — 폴백용
      result_field=$(printf '%s' "$line" | sed -n 's/.*"result":"\(\([^"\\]\|\\.\)*\)".*/\1/p')
    fi
  done

  # assistant 누적 텍스트가 있으면 우선, 없으면 result 필드
  if [ -n "$_AR_RESULT_TEXT" ]; then
    :
  elif [ -n "$result_field" ]; then
    # \n, \" 디코드 (최소)
    _AR_RESULT_TEXT=$(printf '%s' "$result_field" | sed 's/\\n/\n/g; s/\\"/"/g; s/\\\\/\\/g')
  fi
}

# assistant 텍스트 블록 누적 (stream 전체에서 별도 추출)
# stream-json 의 assistant 메시지 content[].text 를 이어붙인다.
#
# [Fix C] 이전 구현: sed 's/.*"text":"\(...\)".*/\1/' 는 greedy 라서
# 한 줄에 text 블록이 여러 개 있을 때 마지막 블록만 반환했다.
# 수정: grep -o 로 각 블록을 개별 추출한 뒤 이어붙인다.
_extract_assistant_text() {
  # 입력: stream-json 전체(파일). grep 으로 assistant 라인만 추려 text 추출.
  local stream_file="$1"
  grep '"type":"assistant"' "$stream_file" 2>/dev/null \
    | grep -o '"text":"\(\([^"\\]\|\\.\)*\)"' \
    | sed 's/^"text":"//; s/"$//' \
    | sed 's/\\n/\n/g; s/\\"/"/g; s/\\t/\t/g; s/\\\\/\\/g'
}

# ─────────────────────────────────────────────────────────
# 시스템 프롬프트 조립
# ─────────────────────────────────────────────────────────
# 게이트웨이 _build_system_prompt 미러: identity 헤더 + SOUL 본문.
# prompt_build 를 재사용해 3-tier(프로젝트 컨텍스트 + SOUL 컨텍스트 + 태스크)를
# 그대로 살린다. 게이트웨이는 raw SOUL body 만 쓰지만, bash 경로는
# prompt_build 가 이미 캐시 최적화된 SOUL 컨텍스트를 만들어 주므로 재사용한다.
_build_agent_system_prompt() {
  local soul_name="$1"
  # identity 헤더 (게이트웨이와 동일 톤)
  local specialty="${SOUL_SPECIALTY:-—}"
  cat <<HEADER
# SOUL Identity
You are **${SOUL_NAME:-$soul_name}** (${SOUL_RANK:-unknown}). Specialty: ${specialty}.
Respond as ${SOUL_NAME:-$soul_name}, staying in your area of expertise. Keep your voice consistent across turns.

HEADER
}

# ─────────────────────────────────────────────────────────
# 메인: agent_run
# ─────────────────────────────────────────────────────────
# agent_run <soul_name> <task_text> [session_id] [--dry-run]
#   - SOUL 파싱 → 시스템 프롬프트 조립 → claude 소환 → 결과/usage 파싱
#   - 성공 시 growth-log 에 비용 포함 기록 (budget_estimate_cost 재사용)
#   - --dry-run: claude argv 만 출력하고 소환하지 않음 (오프라인 테스트)
#   stdout: 최종 어시스턴트 텍스트
#   마지막 줄: <usage> 요약 (파싱 가능)
agent_run() {
  local soul_name="$1"
  local task_text="$2"
  local session_id=""
  local dry_run=0
  # 표시용 max_seconds — AGENT_MAX_SECONDS 가 소환 후 unset 돼도 기본값 유지
  local max_secs="${AGENT_MAX_SECONDS:-300}"

  # 나머지 인자 파싱 (session_id, --dry-run 순서 무관)
  shift 2
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) dry_run=1 ;;
      *)         [ -z "$session_id" ] && session_id="$1" ;;
    esac
    shift
  done

  if [ -z "$soul_name" ] || [ -z "$task_text" ]; then
    echo "[agent-runner] Usage: agent_run <soul_name> <task_text> [session_id] [--dry-run]" >&2
    return 1
  fi

  # claude CLI 가드 (게이트웨이 CLAUDE_CMD is None 체크 미러)
  if [ "$dry_run" -eq 0 ] && ! command -v claude >/dev/null 2>&1; then
    echo "[agent-runner] ERROR: 'claude' CLI를 PATH에서 찾을 수 없습니다." >&2
    echo "[agent-runner] Claude Code CLI를 설치하고 PATH에 추가하세요." >&2
    return 127
  fi

  # (a) SOUL 파싱
  local soul_file
  soul_file=$(_resolve_soul_file "$soul_name")
  if [ -z "$soul_file" ] || [ ! -f "$soul_file" ]; then
    echo "[agent-runner] ERROR: SOUL 파일 없음: ${soul_name}" >&2
    return 1
  fi
  soul_parse "$soul_file"

  # (b) 시스템 프롬프트 = identity 헤더 + prompt_build(SOUL 컨텍스트 + 태스크)
  # 명령 치환은 trailing newline 을 제거하므로 헤더/본문 사이에 명시적 개행 삽입
  local _ar_header _ar_body
  _ar_header="$(_build_agent_system_prompt "$soul_name")"
  _ar_body="$(prompt_build "$soul_name" "$task_text")"
  local system_prompt
  system_prompt="${_ar_header}

${_ar_body}"

  # (c) 모델 매핑 + (d 일부) 도구 CSV
  local model_arg tools_csv
  model_arg=$(_map_model "$SOUL_MODEL")
  tools_csv=$(_tools_csv "$SOUL_TOOLS")

  # 세션 인자 결정: 없거나 0턴이면 --session-id, 기존 세션이면 --resume
  # (게이트웨이 prior_count==0 분기 미러). bash 경로는 세션 메타에 의존하지 않고
  # session_id 전달 여부 + 메타 존재 여부로 판단한다.
  local session_args
  if [ -z "$session_id" ]; then
    session_id=$(_gen_uuid)
    session_args=(--session-id "$session_id")
  elif _agent_session_has_turns "$session_id"; then
    session_args=(--resume "$session_id")
  else
    session_args=(--session-id "$session_id")
  fi

  # (d) claude argv 조립 — 게이트웨이와 동일 + bash 경로 전용 --model/--allowedTools
  local -a argv
  argv=(claude "${_AGENT_CLAUDE_BASE[@]}" "${session_args[@]}"
        --append-system-prompt "$system_prompt"
        --model "$model_arg")

  # [Fix B] disallowedTools 시행 — `--disallowedTools` / `--disallowed-tools` 플래그가
  # 설치된 claude CLI 에 존재함을 확인 (`claude --help 2>&1 | grep -i disallowed`).
  # SOUL_DISALLOWED_TOOLS 가 비어있지 않으면 CLI 에 전달한다.
  local disallowed_csv
  disallowed_csv=$(_tools_csv "$SOUL_DISALLOWED_TOOLS")
  if [ -n "$disallowed_csv" ]; then
    argv+=(--disallowedTools "$disallowed_csv")
  fi

  # [Fix A] maxTurns 시행 — `--max-turns` 플래그가 현재 설치된 claude CLI 에
  # 존재하지 않는다 (`claude --help 2>&1 | grep -iE 'max.?turn'` → 빈 출력).
  # 따라서 SOUL_MAX_TURNS 를 CLI 에 전달할 수 없다.
  # CLAUDE.md "Novice SOUL은 maxTurns 제한 적용 (기본 15턴)" 는 현재 비시행 상태다.
  # CLI 가 해당 플래그를 추가하면 아래 블록을 활성화하라:
  #
  #   if printf '%s' "$SOUL_MAX_TURNS" | grep -qE '^[0-9]+$'; then
  #     argv+=(--max-turns "$SOUL_MAX_TURNS")
  #   fi
  #
  # DOC-CHANGE REQUIRED (다른 에이전트가 처리):
  #   - CLAUDE.md (프로젝트): "Novice SOUL은 maxTurns 제한 적용 (기본 15턴)"
  #     → "maxTurns는 SOUL 메타데이터에 기록되나 CLI 플래그 미지원으로 현재 비시행 (advisory only)"
  #   - skills/README.md 또는 SKILL.md 에 동일 주장이 있을 경우 동일하게 수정.

  # --allowedTools: tools_csv 가 비어 있으면 전달하지 않음 → claude 기본 도구셋 상속.
  # (의도적 동작 — SOUL 에 tools: 가 없으면 제한 없이 실행됨을 허용한다.)
  if [ -n "$tools_csv" ]; then
    argv+=(--allowedTools "$tools_csv")
  fi
  argv+=(-- "$task_text")

  # 타임아웃 프리픽스 결정 (D1) — dry-run 에서는 가시화만, 실제 소환 시에는 prepend.
  local -a _ar_timeout_pfx=()
  read -r -a _ar_timeout_pfx < <(_agent_timeout_cmd)
  local _ar_guard_desc
  if [ "${#_ar_timeout_pfx[@]}" -gt 0 ]; then
    _ar_guard_desc="${_ar_timeout_pfx[*]} (max_seconds=${max_secs})"
  else
    _ar_guard_desc="DISABLED (no timeout/gtimeout — unbounded, max_seconds=${max_secs})"
  fi

  # --dry-run: argv 만 출력 (각 인자 한 줄, 따옴표로 가독성)
  if [ "$dry_run" -eq 1 ]; then
    echo "[agent-runner] DRY-RUN argv (소환 안 함):"
    echo "[agent-runner] runaway guard: timeout=${_ar_guard_desc} cost_cap=${AGENT_MAX_COST_USD:-disabled}"
    local a
    # 실제 소환 시 prepend 될 타임아웃 프리픽스를 명시 (가시성 D3)
    for a in "${_ar_timeout_pfx[@]}" "${argv[@]}"; do
      printf '  %q\n' "$a"
    done
    echo "<usage> soul=${soul_name} model=${model_arg} tools=[${tools_csv}] session=${session_id} mode=${session_args[0]} max_seconds=${max_secs} cost_cap=${AGENT_MAX_COST_USD:-disabled}"
    return 0
  fi

  # (e) 소환 + stream-json 캡처
  # D1 — 벽시계 타임아웃 가드. timeout 프리픽스를 prepend (없으면 한 번 경고).
  local stream_file
  stream_file=$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/agent_run_$$_$RANDOM")
  local rc=0
  local _ar_timed_out=0
  if [ "${#_ar_timeout_pfx[@]}" -gt 0 ]; then
    # timeout 124 → 타임아웃, 137 → KILL(타임아웃 후 강제 종료). 둘 다 타임아웃으로 처리.
    "${_ar_timeout_pfx[@]}" "${argv[@]}" > "$stream_file" 2>/dev/null || rc=$?
    if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
      _ar_timed_out=1
    fi
  else
    echo "[agent-runner] WARNING: timeout/gtimeout 미존재 — claude 소환에 벽시계 가드 없음 (무한정 실행 가능)." >&2
    "${argv[@]}" > "$stream_file" 2>/dev/null || rc=$?
  fi

  # 어시스턴트 텍스트 + result usage 파싱
  _AR_RESULT_TEXT=$(_extract_assistant_text "$stream_file")
  _parse_stream < "$stream_file"

  rm -f "$stream_file"

  # D1 — 타임아웃 시: 결과 텍스트를 명확한 사유로 덮어쓰고 fail 처리.
  # (child 는 timeout(1) 이 SIGTERM/SIGKILL 로 이미 종료시킴 — 추가 kill 불필요.)
  if [ "$_ar_timed_out" -eq 1 ]; then
    _AR_RESULT_TEXT="[agent-runner] TIMEOUT after ${AGENT_MAX_SECONDS}s"
    _AR_IS_ERROR=1
  fi

  # 결과 텍스트 출력
  printf '%s\n' "$_AR_RESULT_TEXT"

  # (f) 성공 시 growth-log 기록 (cost 수학은 budget.sh 재사용 — 중복 금지)
  local result="success"
  [ "$_AR_IS_ERROR" -eq 1 ] && result="fail"
  [ "$rc" -ne 0 ] && result="fail"

  # 세션 마커 기록 — 성공 소환 후 .claude 마커를 써서 후속 호출이 --resume 을 타게 함
  # (_agent_session_has_turns 가 읽는 파일. 지금까지 아무도 쓰지 않아 --resume 갭 존재)
  if [ "$result" = "success" ]; then
    local _ar_sess_dir="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/sessions"
    mkdir -p "$_ar_sess_dir" 2>/dev/null
    : > "${_ar_sess_dir}/${session_id}.claude" 2>/dev/null \
      || touch "${_ar_sess_dir}/${session_id}.claude" 2>/dev/null
  fi

  local total_tokens=$(( _AR_TOKENS_IN + _AR_TOKENS_OUT ))
  local cost="0.000"
  if [ "$total_tokens" -gt 0 ] 2>/dev/null; then
    source "${GOLEM_ROOT}/lib/budget.sh" 2>/dev/null
    # budget_estimate_cost 는 "tokens_in tokens_out cost" 를 출력하지만
    # 우리는 result usage 의 실제 토큰을 쓰므로 cost 만 취한다.
    local cost_data
    cost_data=$(budget_estimate_cost "$model_arg" "$total_tokens" "$_AR_DURATION_MS")
    cost=$(printf '%s' "$cost_data" | awk '{print $3}')
    growth_log_append "$soul_name" "$task_text" "$result" 0 0 "" "" \
      "$_AR_TOKENS_IN" "$_AR_TOKENS_OUT" "$_AR_TOKENS_CACHE" "$cost" "$model_arg" "$_AR_DURATION_MS" >&2

    # D2 — 단일 run 비용 상한 트립와이어 (사후 경고, 사전 차단 아님).
    # AGENT_MAX_COST_USD 설정 시 단일 run 비용이 초과하면 stderr 로 경고.
    # 새 예산 서브시스템을 만들지 않고 budget.sh(budget_estimate_cost)만 재사용한다.
    if [ -n "$AGENT_MAX_COST_USD" ]; then
      local _ar_cost_exceeded
      _ar_cost_exceeded=$(awk "BEGIN {print ($cost > $AGENT_MAX_COST_USD) ? 1 : 0}" 2>/dev/null)
      if [ "${_ar_cost_exceeded:-0}" = "1" ]; then
        echo "[agent-runner] WARNING: run 비용 \$${cost} 가 상한 \$${AGENT_MAX_COST_USD} 를 초과 (soul=${soul_name}, model=${model_arg})." >&2
        # 누적 세션 비용 가시화 (budget.sh 상태 파일이 있으면 — 선택적, 신규 인프라 아님).
        if command -v budget_status >/dev/null 2>&1; then
          local _ar_cum
          _ar_cum=$(budget_status 2>/dev/null | grep -i '비용' | head -1 | tr -s ' ')
          [ -n "$_ar_cum" ] && echo "[agent-runner] 누적 세션:${_ar_cum}" >&2
        fi
      fi
    fi
  else
    growth_log_append "$soul_name" "$task_text" "$result" 0 0 >&2
  fi

  # (g) 스킬 증류 — 임계 도달 시 기존 soul-memory 라이브러리로 lesson 1건 압축 기록
  # (stdout 오염 방지를 위해 stderr 로. 성공 태스크에서만.)
  if [ "$result" = "success" ]; then
    _agent_maybe_distill "$soul_name" >&2
  fi

  # usage 요약 라인 (파싱 가능) — D1: timeout 마커, D3: max_seconds/cost_cap 가시화
  echo "<usage> soul=${soul_name} model=${model_arg} result=${result} tokens_in=${_AR_TOKENS_IN} tokens_out=${_AR_TOKENS_OUT} tokens_cache=${_AR_TOKENS_CACHE} duration_ms=${_AR_DURATION_MS} timeout=${_ar_timed_out} max_seconds=${max_secs} cost_cap=${AGENT_MAX_COST_USD:-disabled}"

  [ "$result" = "fail" ] && return 1
  return 0
}

# ─────────────────────────────────────────────────────────
# 스킬 증류 (D4) — 기존 soul-memory 라이브러리에 lesson 1건 연결만 함
# ─────────────────────────────────────────────────────────
# 임계: 마지막 증류 이후 성공 태스크 5건 누적 시 distilled lesson 1건 기록.
# 새 인프라를 만들지 않고 growth_log_task_count + memory_record 를 재사용한다.
# distilled lesson 은 tags 에 "distilled" 를 달아 카운트 기준으로 삼는다.
_AGENT_DISTILL_THRESHOLD="${AGENT_DISTILL_THRESHOLD:-5}"

_agent_maybe_distill() {
  local soul_name="$1"
  [ -z "$soul_name" ] && return 0

  # soul-memory 라이브러리(memory_record / MEMORY_DIR) 보장
  command -v memory_record >/dev/null 2>&1 || source "${GOLEM_ROOT}/lib/soul-memory.sh"

  # 누적 성공 태스크 수 (메타 이벤트 제외 — growth-log 가 알아서 필터)
  local success_count
  success_count=$(growth_log_task_count "$soul_name")
  success_count=${success_count:-0}
  [ "$success_count" -ge "$_AGENT_DISTILL_THRESHOLD" ] 2>/dev/null || return 0

  # 이미 증류된 lesson 수 (tags 에 distilled 포함)
  local mem_file="${MEMORY_DIR}/${soul_name}.jsonl"
  local distilled_count=0
  if [ -f "$mem_file" ]; then
    distilled_count=$(grep -c '"tags":"[^"]*distilled' "$mem_file" 2>/dev/null | tr -d ' \r')
    distilled_count=${distilled_count:-0}
  fi

  # 임계: 증류 1건당 성공 5건. (distilled+1)*5 도달했을 때만 새로 기록.
  local need=$(( (distilled_count + 1) * _AGENT_DISTILL_THRESHOLD ))
  [ "$success_count" -ge "$need" ] 2>/dev/null || return 0

  # 기존 memory_record 로 압축 lesson 1건 기록 (새 시스템 아님)
  local lesson="${success_count}건 성공 누적 — 안정적으로 처리해온 태스크 패턴을 우선 재사용하고, 검증된 접근을 기본값으로 삼는다."
  memory_record "$soul_name" "distillation@${success_count}-tasks" "$lesson" "distilled,milestone"
}

# 세션이 이전 턴을 가지고 있는지 판단 (--resume vs --session-id)
# .golem/sessions/ 메타 또는 claude 세션 존재 여부로 근사.
# 게이트웨이는 sqlite message_count 를 쓰지만 bash 경로는 파일 기반.
_agent_session_has_turns() {
  local sid="$1"
  [ -z "$sid" ] && return 1
  local sess_dir="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/sessions"
  # claude 세션 마커 파일(있으면) 또는 우리 트랜스크립트에 해당 sid 기록이 있으면 턴 있음
  if [ -f "${sess_dir}/${sid}.claude" ]; then
    return 0
  fi
  return 1
}
