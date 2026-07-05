#!/usr/bin/env bash
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
source "${GOLEM_ROOT}/lib/model-routing.sh"

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
# AGENT_MAX_SECONDS  — claude 소환 벽시계 타임아웃(초).
#   빈 값(기본) = SOUL_EFFORT 기반 자동 결정 (P2-1 effort 실소비 — low=180/medium=300/high=600, 명시 env 우선).
#   명시 설정 시 해당 값 최우선 사용. 게이트웨이 MAX_RUN_SECONDS=300 과 동일 역할.
# AGENT_MAX_COST_USD — 단일 run 비용 상한(USD). 빈 값=비활성(기본). 초과 시 stderr 경고
#                      (사후 트립와이어 — 가시성 가드일 뿐 사전 차단 아님).
AGENT_MAX_SECONDS="${AGENT_MAX_SECONDS:-}"
AGENT_MAX_COST_USD="${AGENT_MAX_COST_USD:-}"

# D4 — 예산 사전 차단 (P0-3). budget-state.json 의 status 가 exceeded 면
# 소환 자체를 거부한다 (기존 D2 비용 트립와이어는 사후 경고만 했음).
# 우회: GOLEM_BUDGET_OVERRIDE=1 / 리셋: forge budget reset
_agent_budget_preflight() {
  [ "${GOLEM_BUDGET_OVERRIDE:-0}" = "1" ] && return 0
  local bf="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/budget-state.json"
  [ -f "$bf" ] || return 0
  local st
  st=$(grep -o '"status":"[^"]*"' "$bf" | sed 's/"status":"//;s/"//')
  if [ "$st" = "exceeded" ]; then
    echo "[agent-runner] BLOCKED: 세션 예산 초과 (budget-state.json status=exceeded) — 소환 거부." >&2
    echo "[agent-runner] 우회: GOLEM_BUDGET_OVERRIDE=1, 리셋: forge budget reset" >&2
    return 1
  fi
  return 0
}

# ─────────────────────────────────────────────────────────
# 런 트래젝토리 영속화 (Phase A — docs/OBSERVABILITY_PLAN.md G1/G2/G4/G5)
# ─────────────────────────────────────────────────────────
# stream-json 을 버리는 대신 .golem/runs/<run_id>.jsonl 로 보존하고
# 1줄 meta 사이드카(spec/run-meta.schema.json 계약)를 남긴다.
# - 마스킹+보존은 sed 단일 패스 (G2: 추가 스캔 최소)
# - 실패는 절대 런을 죽이지 않는다 (전부 soft-fail)
# GOLEM_RUNS_KEEP   — 보존 개수 롤링 (기본 200)
# GOLEM_RUNS_DISABLE=1 — 영속화 끄기 (기존 rm 동작)

# 보존 개수 초과분 삭제 (jsonl + meta 쌍, mtime 역순)
_agent_runs_gc() {
  local dir="$1"
  local keep="${GOLEM_RUNS_KEEP:-200}"
  printf '%s' "$keep" | grep -qE '^[0-9]+$' || keep=200
  local excess f
  excess=$(ls -1t "$dir"/*.jsonl 2>/dev/null | tail -n +"$((keep + 1))")
  [ -z "$excess" ] && return 0
  while IFS= read -r f; do
    rm -f "$f" "${f%.jsonl}.meta.json" 2>/dev/null
  done <<EOF_GC
$excess
EOF_GC
  return 0
}

# _agent_persist_run <stream_file> <run_id> <session_id> <soul> <model> <result> <cost> <ts_start>
# 호출 후 stream_file 은 항상 제거된다 (보존 성공 시 마스킹 사본만 남음).
_agent_persist_run() {
  local stream_file="$1" run_id="$2" session_id="$3" soul_name="$4" model="$5"
  local result="$6" cost="$7" ts_start="$8"

  if [ "${GOLEM_RUNS_DISABLE:-0}" = "1" ] || [ ! -f "$stream_file" ]; then
    rm -f "$stream_file" 2>/dev/null
    return 0
  fi

  local runs_dir="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/runs"
  mkdir -p "$runs_dir" 2>/dev/null || { rm -f "$stream_file"; return 0; }
  local dest="${runs_dir}/${run_id}.jsonl"

  # 시크릿 마스킹 + 보존 — 단일 패스 (G5, gateway runs_store.py 와 동일 규칙)
  if ! sed -E \
    -e 's/sk-[A-Za-z0-9_-]{10,}/***MASKED***/g' \
    -e 's/ghp_[A-Za-z0-9]{20,}/***MASKED***/g' \
    -e 's/(ANTHROPIC|OPENAI)[A-Z_]*KEY["=: ]+[^",[:space:]]+/\1_KEY=***MASKED***/g' \
    "$stream_file" > "$dest" 2>/dev/null; then
    rm -f "$stream_file" "$dest" 2>/dev/null
    return 0
  fi
  rm -f "$stream_file" 2>/dev/null

  # tool_counts — 마스킹 사본 1패스 근사 카운트 (stream-json tool_use "name" 필드)
  local tool_counts
  tool_counts=$(grep -o '"name":"[A-Za-z_][A-Za-z0-9_]*"' "$dest" 2>/dev/null \
    | sed 's/^"name"://' | sort | uniq -c \
    | awk '{gsub(/"/,"",$2); printf "%s\"%s\":%s", sep, $2, $1; sep=","}')
  tool_counts="{${tool_counts}}"

  # meta 사이드카 — 이미 파싱된 _AR_* 재사용 (추가 스캔 0)
  printf '{"run_id":"%s","session_id":"%s","soul":"%s","model":"%s","source":"bash","ts_start":"%s","duration_ms":%s,"tokens_in":%s,"tokens_out":%s,"tokens_cache":%s,"tokens_cache_read":%s,"tokens_cache_creation":%s,"cost_usd":%s,"result":"%s","tool_counts":%s}\n' \
    "$run_id" "$session_id" "$soul_name" "$model" "$ts_start" \
    "${_AR_DURATION_MS:-0}" "${_AR_TOKENS_IN:-0}" "${_AR_TOKENS_OUT:-0}" "${_AR_TOKENS_CACHE:-0}" \
    "${_AR_TOKENS_CACHE_READ:-0}" "${_AR_TOKENS_CACHE_CREATE:-0}" \
    "${cost:-0.000}" "$result" "$tool_counts" \
    > "${runs_dir}/${run_id}.meta.json" 2>/dev/null

  _agent_runs_gc "$runs_dir"
  return 0
}

# timeout 명령 프리픽스 배열을 stdout 으로 출력한다 (진단/탐지 전용).
# - GNU coreutils `timeout` (리눅스) 또는 `gtimeout` (macOS coreutils) 탐지.
# - 둘 다 없으면 빈 출력 (Windows Git Bash 기본 상태).
# NOTE: agent_run 은 이 프리픽스를 prepend 하지 않는다 — MSYS `timeout` 이 네이티브
#   Windows claude.exe 에 시그널을 전달하지 못하므로, 바이너리 유무와 무관하게
#   소환 지점의 bash 워치독(_agent_kill_tree 루프)이 벽시계 가드를 담당한다.
#   즉 timeout/gtimeout 부재(Windows Git Bash)여도 가드는 비활성화되지 않는다.
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

# 프로세스 트리 강제 종료 (벽시계 워치독용).
# Git Bash 의 `timeout`/`kill` 은 네이티브 Windows 자식(claude.exe)에 시그널을
# 전달하지 못해 무한 대기/좀비가 된다. 그래서 winpid 기반 `taskkill //F //T` 로
# 트리를 먼저 죽이고, POSIX 에서는 kill 로 폴백한다. dead pid 여도 무해(rc 0).
_agent_kill_tree() {
  local pid="$1"
  [ -n "$pid" ] || return 0
  local winpid=""
  [ -r "/proc/${pid}/winpid" ] && winpid=$(cat "/proc/${pid}/winpid" 2>/dev/null)
  if [ -n "$winpid" ] && command -v taskkill >/dev/null 2>&1; then
    taskkill //F //T //PID "$winpid" >/dev/null 2>&1 || true
  fi
  kill -TERM "$pid" 2>/dev/null || true
  kill -KILL "$pid" 2>/dev/null || true
  return 0
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
  _AR_TOKENS_CACHE_READ=0
  _AR_TOKENS_CACHE_CREATE=0
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
      # read/creation 분리 보존 — 적중률(read/(read+creation+input)) 측정용.
      # tokens_cache 합산은 기존 소비자(eval.sh/growth-log) 호환으로 유지.
      _AR_TOKENS_CACHE_READ=${cr_t:-0}
      _AR_TOKENS_CACHE_CREATE=${cc_t:-0}
      _AR_TOKENS_CACHE=$(( ${cr_t:-0} + ${cc_t:-0} ))
      # result 라인은 보통 "result" 키에 최종 텍스트를 담음 — 폴백용
      result_field=$(printf '%s' "$line" | awk '
        {
          pat = "\"result\":\""
          plen = length(pat); n = length($0); i = 1
          while (i <= n - plen + 1) {
            if (substr($0, i, plen) == pat) {
              i += plen; out = ""
              while (i <= n) {
                c = substr($0, i, 1)
                if (c == "\\") {
                  if (i < n) { d = substr($0, i+1, 1); out = out c d; i += 2; continue }
                } else if (c == "\"") { printf "%s", out; exit 0 }
                out = out c; i++
              }
              exit 0
            }
            i++
          }
        }')
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
  # max_secs 는 soul_parse 이후 effort 기반으로 재해석된다 (아래 참조).
  # 여기서는 플레이스홀더만 선언 — soul_parse 전이라 SOUL_EFFORT 미확정.
  local max_secs=""

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

  # D4 — 예산 사전 차단 (P0-3): dry-run 은 비용이 없으므로 통과
  if [ "$dry_run" -eq 0 ] && ! _agent_budget_preflight; then
    return 1
  fi

  # (a) SOUL 파싱
  local soul_file
  soul_file=$(_resolve_soul_file "$soul_name")
  if [ -z "$soul_file" ] || [ ! -f "$soul_file" ]; then
    echo "[agent-runner] ERROR: SOUL 파일 없음: ${soul_name}" >&2
    return 1
  fi
  soul_parse "$soul_file"

  # P2-1 effort 실소비 — low=180/medium=300/high=600, 명시 env 우선.
  # AGENT_MAX_SECONDS 가 명시(비어있지 않음)이면 그 값 최우선;
  # 비어 있으면 SOUL_EFFORT 기반 자동 결정.
  if [ -n "${AGENT_MAX_SECONDS:-}" ]; then
    max_secs="$AGENT_MAX_SECONDS"
  else
    case "${SOUL_EFFORT:-}" in
      low)    max_secs=180 ;;
      medium) max_secs=300 ;;
      high)   max_secs=600 ;;
      *)      max_secs=300 ;;
    esac
  fi

  # P1-1 SOUL_MAX_TURNS — 양의 정수면 advisory 주입 + 하드 집행 카운터로 파싱.
  local _ar_max_turns=0
  if printf '%s' "${SOUL_MAX_TURNS:-}" | grep -qE '^[1-9][0-9]*$'; then
    _ar_max_turns="$SOUL_MAX_TURNS"
  fi
  # P1-1 턴 캡 — SOUL_MAX_TURNS>0 이면 기본 활성.
  # 폴링(1s) 기반 집행 — 워치독이 stream-json 의 "type":"assistant" 이벤트 라인 수를
  # 1초 주기로 재확인해, 저속 런어웨이는 캡 초과 시점에 _agent_kill_tree 로 중단한다.
  # 폴 사이(<1s)에 캡을 넘기고 스스로 끝나버리는 고속 버스트는 kill 이 개입할 기회가
  # 없으므로, 자식 종료 후 최종 카운트를 다시 세어 turn_cap 으로 사후 정산한다
  # (CLI --max-turns 부재를 하네스가 대체. 두 경로 모두 result=turn_cap 으로 수렴).
  # 캡은 invocation 단위로만 유효하다 — --resume 으로 이전 세션을 이어도 새 stream_file
  # 이 매 호출마다 새로 생성되므로 카운트는 0부터 다시 시작한다(누적되지 않음).
  # 킬스위치: GOLEM_TURN_CAP_ENFORCE=0. 캡 미설정(SOUL_MAX_TURNS 비어있음)이면 무캡.
  local _ar_turn_cap_active=0
  if [ "${GOLEM_TURN_CAP_ENFORCE:-1}" != "0" ] && [ "${_ar_max_turns:-0}" -gt 0 ] 2>/dev/null; then
    _ar_turn_cap_active=1
  fi

  # (b) 시스템 프롬프트 = identity 헤더 + 정적 SOUL 컨텍스트만 (byte-stable).
  # 휘발 값(이력/메모리)과 태스크는 유저 메시지로 — 시스템 프롬프트가 런마다
  # 동일해야 API 프롬프트 캐시가 크로스-런으로 히트한다 (5분 TTL 내).
  # 명령 치환은 trailing newline 을 제거하므로 헤더/본문 사이에 명시적 개행 삽입
  local _ar_header _ar_body
  _ar_header="$(_build_agent_system_prompt "$soul_name")"
  _ar_body="$(prompt_build_static "$soul_name")"
  local system_prompt
  system_prompt="${_ar_header}

${_ar_body}"

  # 유저 메시지 = 휘발 블록(이력/메모리) + 태스크
  local _ar_user_msg
  _ar_user_msg="$(prompt_build_task_block "$soul_name" "$task_text")"

  # P1-1 턴 캡 — claude CLI 가 --max-turns 를 미지원(설치본 --help 확인: --max-budget-usd
  # 만 존재)하므로 CLI 레벨 집행 불가. SOUL_MAX_TURNS 가 양의 정수면:
  #   ① advisory 로 유저 메시지에 주입 (아래) — 모델이 스스로 수렴하게 유도
  #   ② 폴링(1s) 기반 집행 — 워치독이 stream 의 assistant 이벤트를 카운트, 저속
  #      런어웨이는 캡 초과 시 kill, 폴 사이 고속 버스트는 자식 종료 후 사후 정산
  #      (_ar_turn_cap_active, 소환 지점 참조. 두 경로 모두 result=turn_cap 으로 기록됨)
  #      캡은 invocation 단위 — --resume 시에도 이번 호출의 stream_file 기준으로 리셋된다.
  if [ "${_ar_max_turns:-0}" -gt 0 ] 2>/dev/null; then
    _ar_user_msg="${_ar_user_msg}

[실행 가이드] 이 작업은 최대 ${_ar_max_turns} 턴(도구 호출 왕복) 내에 완료하는 것을 목표로 하라. 불필요한 탐색을 줄이고 핵심 변경에 집중하라."
  fi

  # (c) 모델 매핑 + (d 일부) 도구 CSV
  # P2-1 라우팅 — SOUL_MODEL 이 CLI 인자가 되는 유일한 심(seam).
  # route_model: frontmatter 명시(비어있지 않고 auto 아님)는 그대로, 빈/auto 는
  # 역할·랭크 정적 테이블로 결정 + GOLEM_MODEL_ESCALATE 재시도 승급 (lib/model-routing.sh).
  # AGENT_MODEL_OVERRIDE — 라우팅 결과까지 1회성으로 교체하는 최우선 훅 (P2-3 eval
  # 모델 비교 등). 우선순위: OVERRIDE > route_model > _map_model 기본값.
  local model_arg tools_csv _ar_routed_model
  _ar_routed_model=$(route_model "$SOUL_MODEL" "$SOUL_ROLE" "$SOUL_RANK" "$SOUL_IS_COORDINATOR")
  model_arg=$(_map_model "${AGENT_MODEL_OVERRIDE:-$_ar_routed_model}")
  tools_csv=$(_tools_csv "$SOUL_TOOLS")

  # 런 식별자 + 시작 시각 (Phase A 트래젝토리 meta 용 — 세션 uuid 와 별개)
  local run_id
  run_id=$(_gen_uuid)
  local _ar_ts_start
  _ar_ts_start=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

  # 세션 인자 결정: 없거나 0턴이면 --session-id, 기존 세션이면 --resume
  # (게이트웨이 prior_count==0 분기 미러). bash 경로는 세션 메타에 의존하지 않고
  # session_id 전달 여부 + 메타 존재 여부로 판단한다.
  # P2-4 발견: forge 세션 ID(sess_*)가 그대로 들어오면 claude 가
  # "Invalid session ID. Must be a valid UUID." 로 즉시 거부 → run 전체 fail.
  # UUID 형식이 아니면 경고 후 버리고 새 UUID 를 생성한다 (forge 세션과
  # claude 세션은 별개 체계 — 연결은 세션 메타가 담당).
  if [ -n "$session_id" ] && ! printf '%s' "$session_id" | grep -qiE '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'; then
    echo "[agent-runner] WARNING: session_id 가 UUID 형식이 아님('${session_id}') — 무시하고 세션 선택 위임" >&2
    session_id=""
  fi
  local session_args _ar_sess_mode
  if [ -n "$session_id" ]; then
    # 명시적 UUID — 호출자 의도 존중 (마커 있으면 resume)
    if _agent_session_has_turns "$session_id"; then
      session_args=(--resume "$session_id"); _ar_sess_mode="resume"
    else
      session_args=(--session-id "$session_id"); _ar_sess_mode="fresh"
    fi
  else
    # per-SOUL recency-gated resume (P2-1 캐시 레버)
    local _ar_pick; _ar_pick=$(_agent_pick_session "$soul_name")
    session_id=${_ar_pick%% *}; _ar_sess_mode=${_ar_pick##* }
    if [ "$_ar_sess_mode" = "resume" ]; then
      session_args=(--resume "$session_id")
      echo "[agent-runner] 세션 재사용(--resume) soul=${soul_name} sid=${session_id:0:8} — 캐시 적중 시도" >&2
    else
      session_args=(--session-id "$session_id")
    fi
  fi

  # (d)+(e) 조립·소환 루프 — --resume 즉사 시 새 세션으로 1회 재시도하기 위해
  # argv 조립부터 파싱까지를 감싼다 (P2-2 폴백, 아래 continue 지점 참조).
  local _ar_attempt=0
  while :; do
  _ar_attempt=$((_ar_attempt + 1))

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

  # [Fix A → P1-1 해소] maxTurns 시행 — `--max-turns` 플래그는 여전히 claude CLI 에
  # 없지만(`claude --help 2>&1 | grep -iE 'max.?turn'` → 빈 출력), 하네스가 대체
  # 집행한다: 워치독이 stream-json assistant 이벤트 라인 수를 1초 폴링으로 재확인해
  # 저속 런어웨이는 캡 초과 시 _agent_kill_tree 로 중단하고, 폴 사이 고속 버스트는
  # 자식 정상 종료 후 최종 카운트로 사후 정산한다 (두 경로 모두 result=turn_cap).
  # CLI 가 플래그를 추가하면 아래로 이관 가능:
  #
  #   if printf '%s' "$SOUL_MAX_TURNS" | grep -qE '^[0-9]+$'; then
  #     argv+=(--max-turns "$SOUL_MAX_TURNS")
  #   fi

  # --allowedTools: tools_csv 가 비어 있으면 전달하지 않음 → claude 기본 도구셋 상속.
  # (의도적 동작 — SOUL 에 tools: 가 없으면 제한 없이 실행됨을 허용한다.)
  if [ -n "$tools_csv" ]; then
    argv+=(--allowedTools "$tools_csv")
  fi
  argv+=(-- "$_ar_user_msg")

  # 가드 가시성 (D1/D3) — 실제 벽시계 가드는 아래 소환 지점의 bash 워치독이며,
  # timeout/gtimeout 바이너리 유무와 무관하게 max_secs>0 이면 항상 동작한다
  # (Windows Git Bash 에 GNU timeout 이 없어도 무제한 실행되지 않음 — BACKLOG P1).
  local _ar_guard_desc
  if [ "${max_secs:-0}" -gt 0 ] 2>/dev/null; then
    _ar_guard_desc="bash-watchdog (max_seconds=${max_secs})"
  else
    _ar_guard_desc="DISABLED (max_seconds=${max_secs} — unbounded)"
  fi

  # --dry-run: argv 만 출력 (각 인자 한 줄, 따옴표로 가독성)
  if [ "$dry_run" -eq 1 ]; then
    echo "[agent-runner] DRY-RUN argv (소환 안 함):"
    echo "[agent-runner] runaway guard: timeout=${_ar_guard_desc} cost_cap=${AGENT_MAX_COST_USD:-disabled}"
    local a
    for a in "${argv[@]}"; do
      printf '  %q\n' "$a"
    done
    echo "<usage> soul=${soul_name} model=${model_arg} tools=[${tools_csv}] session=${session_id} mode=${session_args[0]} max_seconds=${max_secs} cost_cap=${AGENT_MAX_COST_USD:-disabled}"
    return 0
  fi

  # (e) 소환 + stream-json 캡처
  # D1 — 벽시계 타임아웃 가드. timeout 프리픽스를 prepend (없으면 한 번 경고).
  # P0-4 — SOUL 컨텍스트 env 주입: child claude 세션의 훅(guard-novice,
  # auto-growth-log)이 누가 실행 중인지 식별하도록 env 프리픽스로 전달.
  # export 가 아닌 env(1) 프리픽스라 호스트 셸에 누출되지 않는다.
  local -a _ar_soul_env
  _ar_soul_env=(env "GOLEM_SOUL_NAME=${SOUL_NAME}" "GOLEM_SOUL_RANK=${SOUL_RANK}")
  local stream_file
  stream_file=$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/agent_run_$$_$RANDOM")
  local rc=0
  local _ar_timed_out=0
  local _ar_turn_capped=0
  # D1 — 벽시계 가드. MSYS/Git Bash 의 `timeout` 은 네이티브 Windows claude.exe 에
  # 시그널을 전달하지 못해 무한 대기(timeout 좀비)했다 → 단계가 'running' 으로 영구
  # 멈춤. 그래서 claude 를 백그라운드로 띄우고 워치독이 데드라인 초과 시 프로세스
  # 트리를 _agent_kill_tree(taskkill//kill)로 강제 종료한다. 모든 플랫폼 공통 경로.
  # P1-1 — 같은 워치독 루프가 턴 캡도 집행한다: stream 파일의 assistant 이벤트
  # 라인("type":"assistant")을 1초 주기로 폴링해, 캡 초과 시점에 트리를 kill.
  # 폴링 주기(1s)보다 빠르게 캡을 넘기고 스스로 종료하는 고속 버스트는 워치독이
  # kill 할 기회를 못 잡으므로, 자식 종료 직후 최종 카운트를 다시 세어 turn_cap 으로
  # 사후 정산한다(아래 wait 이후 elif 분기) — killed 경로는 그대로 유지된다.
  # 워치독은 subshell 이라 부모 변수에 쓸 수 없으므로 벽시계 killflag 와 동일한
  # 마커 파일 패턴(turnflag)으로 사유를 부모에 전달한다.
  if [ "${max_secs:-0}" -gt 0 ] 2>/dev/null || [ "$_ar_turn_cap_active" -eq 1 ]; then
    local _ar_killflag="${stream_file}.killed"
    local _ar_turnflag="${stream_file}.turncap"
    rm -f "$_ar_killflag" "$_ar_turnflag"
    "${_ar_soul_env[@]}" "${argv[@]}" > "$stream_file" 2>/dev/null &
    local _ar_child=$!
    (
      _ar_w=0
      while :; do
        kill -0 "$_ar_child" 2>/dev/null || exit 0   # 자식이 먼저 끝남 → 워치독 종료
        # P1-1 턴 캡 — assistant 이벤트 수가 캡을 초과하면 즉시 중단
        if [ "$_ar_turn_cap_active" -eq 1 ]; then
          # 앵커(^{"type":"assistant") — envelope 라인만 매칭한다. 앵커 없으면
          # assistant 메시지 "text" 본문에 리터럴 "type":"assistant" 문자열이
          # (예: 로그 인용, 튜토리얼 설명) 포함될 때 오카운트로 조기 kill 될 수 있다.
          _ar_tc=$(grep -c '^{"type":"assistant"' "$stream_file" 2>/dev/null | tr -d ' \r')
          if [ "${_ar_tc:-0}" -gt "$_ar_max_turns" ] 2>/dev/null; then
            : > "$_ar_turnflag"                      # 턴 캡 표식
            _agent_kill_tree "$_ar_child"
            exit 0
          fi
        fi
        # D1 벽시계 — max_secs>0 일 때만 (턴 캡 단독 활성 시 벽시계 무제한)
        if [ "${max_secs:-0}" -gt 0 ] 2>/dev/null && [ "$_ar_w" -ge "$max_secs" ]; then
          : > "$_ar_killflag"                        # 타임아웃 표식
          _agent_kill_tree "$_ar_child"
          exit 0
        fi
        sleep 1
        _ar_w=$((_ar_w + 1))
      done
    ) &
    local _ar_wd=$!
    # set -e 안전 — wait 가 non-zero 면 || 로 흡수 (rc 는 위에서 0 초기화).
    # (tests/bats/run.sh 는 set -euo pipefail; forge.sh 는 의도적으로 set -e 미사용)
    wait "$_ar_child" 2>/dev/null || rc=$?
    kill "$_ar_wd" 2>/dev/null || true               # 자식이 먼저 끝났으면 워치독 취소
    wait "$_ar_wd" 2>/dev/null || true
    if [ -f "$_ar_turnflag" ]; then
      _ar_turn_capped=1
      rc=125
    elif [ -f "$_ar_killflag" ]; then
      _ar_timed_out=1
      rc=124
    elif [ "$_ar_turn_cap_active" -eq 1 ]; then
      # 사후 정산(post-run reconciliation) — 자식이 kill 없이 정상 종료했더라도,
      # 폴링(1s) 간격 사이에 캡을 넘긴 뒤 곧바로 끝나버리는 고속 버스트는 워치독이
      # kill 할 기회를 못 잡는다. 자식 종료 후 최종 assistant 라인 수를 다시 세어
      # 캡 초과면 turn_cap 으로 분류한다 (killed 경로와 달리 kill 은 발생하지 않음).
      local _ar_tc_final
      _ar_tc_final=$(grep -c '^{"type":"assistant"' "$stream_file" 2>/dev/null | tr -d ' \r')
      if [ "${_ar_tc_final:-0}" -gt "$_ar_max_turns" ] 2>/dev/null; then
        _ar_turn_capped=1
        rc=1
      fi
    fi
    rm -f "$_ar_killflag" "$_ar_turnflag"
  else
    echo "[agent-runner] WARNING: max_secs<=0 — claude 소환에 벽시계 가드 없음 (무한정 실행 가능)." >&2
    "${_ar_soul_env[@]}" "${argv[@]}" > "$stream_file" 2>/dev/null || rc=$?
  fi

  # 어시스턴트 텍스트 + result usage 파싱
  _AR_RESULT_TEXT=$(_extract_assistant_text "$stream_file")
  _parse_stream < "$stream_file"

  # P2-2 폴백 — --resume 즉사 복구. 포인터 세션이 다른 작업 디렉토리에서
  # 생성됐거나 만료됐으면 claude 가 "No conversation found" 류로 아무 것도
  # 출력하지 않고 즉시 실패한다 (tokens 0). 이 경우 포인터를 폐기하고
  # 새 세션으로 정확히 1회 재소환한다 (라이브 스모크가 잡은 실결함).
  if [ "$_ar_attempt" -eq 1 ] && [ "$_ar_sess_mode" = "resume" ] && [ "$_ar_timed_out" -eq 0 ] \
     && [ "$_ar_turn_capped" -eq 0 ] \
     && { [ "$rc" -ne 0 ] || [ "${_AR_IS_ERROR:-0}" -eq 1 ]; } \
     && [ "$(( ${_AR_TOKENS_IN:-0} + ${_AR_TOKENS_OUT:-0} ))" -eq 0 ]; then
    echo "[agent-runner] WARNING: --resume 소환 즉사 (sid=${session_id:0:8}) — 포인터 폐기, 새 세션으로 재시도" >&2
    rm -f "$(_agent_ptr_file "$soul_name")" 2>/dev/null
    rm -f "$stream_file" 2>/dev/null
    session_id=$(_gen_uuid)
    session_args=(--session-id "$session_id")
    _ar_sess_mode="fresh"
    rc=0
    continue
  fi
  break
  done   # ── (d)+(e) 조립·소환 루프 끝

  # stream_file 은 여기서 지우지 않는다 — result/cost 확정 후
  # _agent_persist_run 이 마스킹 보존 + 제거를 담당한다 (Phase A).

  # D1 — 타임아웃 시: 결과 텍스트를 명확한 사유로 덮어쓰고 fail 처리.
  # (child 는 워치독이 _agent_kill_tree(taskkill//kill)로 이미 종료시킴 — 추가 kill 불필요.)
  if [ "$_ar_timed_out" -eq 1 ]; then
    _AR_RESULT_TEXT="[agent-runner] TIMEOUT after ${max_secs}s"
    _AR_IS_ERROR=1
  fi

  # P1-1 — 턴 캡 초과 시: 사유를 명시하고 fail 계열(turn_cap) 처리.
  # rc=125 는 워치독이 폴링(1s) 중 캡 초과를 감지해 kill 한 경로(타임아웃 경로와
  # 동일 계약). 그 외(rc=1)는 폴 사이 고속 버스트가 kill 없이 스스로 종료된 뒤
  # 사후 정산으로 turn_cap 분류된 경로 — 메시지로 구분해 kill 여부를 오도하지 않는다.
  if [ "$_ar_turn_capped" -eq 1 ]; then
    if [ "$rc" -eq 125 ]; then
      _AR_RESULT_TEXT="[agent-runner] TURN CAP: assistant 턴 ${_ar_max_turns} 초과 — 프로세스 강제 종료"
    else
      _AR_RESULT_TEXT="[agent-runner] TURN CAP: assistant 턴 ${_ar_max_turns} 초과 (사후 정산 — 폴 사이 고속 버스트, kill 없이 종료됨)"
    fi
    _AR_IS_ERROR=1
  fi

  # 결과 텍스트 출력
  printf '%s\n' "$_AR_RESULT_TEXT"

  # (f) 성공 시 growth-log 기록 (cost 수학은 budget.sh 재사용 — 중복 금지)
  local result="success"
  [ "$_AR_IS_ERROR" -eq 1 ] && result="fail"
  [ "$rc" -ne 0 ] && result="fail"
  [ "$_ar_turn_capped" -eq 1 ] && result="turn_cap"   # P1-1 — 구분 기록

  # 세션 마커 기록 — 성공 소환 후 .claude 마커를 써서 후속 호출이 --resume 을 타게 함
  # (_agent_session_has_turns 가 읽는 파일. 지금까지 아무도 쓰지 않아 --resume 갭 존재)
  if [ "$result" = "success" ]; then
    local _ar_sess_dir="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/sessions"
    mkdir -p "$_ar_sess_dir" 2>/dev/null
    : > "${_ar_sess_dir}/${session_id}.claude" 2>/dev/null \
      || touch "${_ar_sess_dir}/${session_id}.claude" 2>/dev/null
    # per-SOUL 세션 포인터 갱신 — 후속 동일-SOUL 소환이 윈도 내면 --resume 으로
    # 캐시 재사용 (명시적 UUID 가 외부에서 주입된 경우는 포인터를 건드리지 않음)
    _agent_ptr_update "$soul_name" "$session_id" "$_ar_sess_mode"
  fi

  local total_tokens=$(( _AR_TOKENS_IN + _AR_TOKENS_OUT ))
  local cost="0.000"
  if [ "$total_tokens" -gt 0 ] 2>/dev/null; then
    source "${GOLEM_ROOT}/lib/budget.sh" 2>/dev/null
    # budget_estimate_cost 는 "tokens_in tokens_out cost" 를 출력하지만
    # 우리는 result usage 의 실제 토큰을 쓰므로 cost 만 취한다.
    # 캐시 read/creation 토큰도 전달 — 캐시 위주 런 $0.000 과소집계 방지 (P3).
    local cost_data
    cost_data=$(budget_estimate_cost "$model_arg" "$total_tokens" "$_AR_DURATION_MS" \
      "${_AR_TOKENS_CACHE_READ:-0}" "${_AR_TOKENS_CACHE_CREATE:-0}")
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

  # 런 트래젝토리 영속화 (Phase A) — result/cost 확정 후 1회.
  # meta result 는 중단 사유를 구분해 기록 (스키마: success|fail|timeout|turn_cap)
  local _ar_meta_result="$result"
  [ "$_ar_timed_out" -eq 1 ] && _ar_meta_result="timeout"
  _agent_persist_run "$stream_file" "$run_id" "$session_id" "$soul_name" "$model_arg" \
    "$_ar_meta_result" "$cost" "$_ar_ts_start"

  # (g) 스킬 증류 — 임계 도달 시 기존 soul-memory 라이브러리로 lesson 1건 압축 기록
  # (stdout 오염 방지를 위해 stderr 로. 성공 태스크에서만.)
  if [ "$result" = "success" ]; then
    _agent_maybe_distill "$soul_name" >&2
  fi

  # usage 요약 라인 (파싱 가능) — D1: timeout 마커, D3: max_seconds/cost_cap 가시화
  echo "<usage> soul=${soul_name} model=${model_arg} result=${result} run=${run_id} session=${_ar_sess_mode:-fresh} tokens_in=${_AR_TOKENS_IN} tokens_out=${_AR_TOKENS_OUT} tokens_cache=${_AR_TOKENS_CACHE} cache_read=${_AR_TOKENS_CACHE_READ:-0} cache_creation=${_AR_TOKENS_CACHE_CREATE:-0} duration_ms=${_AR_DURATION_MS} timeout=${_ar_timed_out} turn_cap=${_ar_turn_capped} max_seconds=${max_secs} max_turns=${_ar_max_turns:-0} cost_cap=${AGENT_MAX_COST_USD:-disabled}"

  [ "$result" = "success" ] || return 1
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

# ── 캐시 적중 레버 (P2-1): 같은 SOUL 연속 소환을 같은 claude 세션으로 --resume ──
# byte-stable 시스템 프롬프트(75dc905)가 캐시 TTL(5분) 내에서 cache_read 되도록
# per-SOUL 세션 포인터를 유지한다. forge sess_* 는 claude 가 거부하는 비-UUID라
# 지금까지 매 run 새 세션 → 캐시 미적중이었다(--resume 인프라 사문화).
# recency 게이트가 핵심: 윈도(캐시 TTL) 초과 후 resume 는 식은 누적 컨텍스트만
# 비싸지므로 그때는 새 세션이 같거나 낫다. 턴캡으로 컨텍스트 무한 증식도 차단.
GOLEM_RESUME_WINDOW_SEC="${GOLEM_RESUME_WINDOW_SEC:-300}"
GOLEM_RESUME_MAX_TURNS="${GOLEM_RESUME_MAX_TURNS:-8}"

_agent_ptr_file() {
  printf '%s/soul-%s.ptr' "${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/sessions" "$1"
}

# 세션 선택 — echoes "<uuid> resume" (윈도 내 따뜻한 세션) 또는 "<newuuid> fresh".
_agent_pick_session() {
  local soul="$1"
  local ptr; ptr=$(_agent_ptr_file "$soul")
  if [ "${GOLEM_RESUME_DISABLE:-0}" = "1" ] || [ ! -f "$ptr" ]; then
    printf '%s fresh' "$(_gen_uuid)"; return
  fi
  local p_uuid p_epoch p_turns now age
  read -r p_uuid p_epoch p_turns < "$ptr" 2>/dev/null
  now=$(date +%s 2>/dev/null || echo 0)
  age=$(( now - ${p_epoch:-0} ))
  if [ -n "$p_uuid" ] \
     && [ "${p_epoch:-0}" -gt 0 ] \
     && [ "$age" -ge 0 ] && [ "$age" -le "$GOLEM_RESUME_WINDOW_SEC" ] \
     && [ "${p_turns:-0}" -lt "$GOLEM_RESUME_MAX_TURNS" ] \
     && [ -f "${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/sessions/${p_uuid}.claude" ]; then
    printf '%s resume' "$p_uuid"
  else
    printf '%s fresh' "$(_gen_uuid)"
  fi
}

# 성공 소환 후 포인터 갱신 — fresh 면 turn=1, resume 면 turn+1.
_agent_ptr_update() {
  local soul="$1" uuid="$2" mode="$3"
  local ptr; ptr=$(_agent_ptr_file "$soul")
  local turns=1 now
  now=$(date +%s 2>/dev/null || echo 0)
  if [ "$mode" = "resume" ] && [ -f "$ptr" ]; then
    local _u _e _t; read -r _u _e _t < "$ptr" 2>/dev/null
    turns=$(( ${_t:-0} + 1 ))
  fi
  local tmp="${ptr}.tmp.$$"
  printf '%s %s %s\n' "$uuid" "$now" "$turns" > "$tmp" 2>/dev/null && mv -f "$tmp" "$ptr" 2>/dev/null
}
