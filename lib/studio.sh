#!/usr/bin/env bash
# studio.sh — Flow Studio (docs/STUDIO_PLAN.md §2/§3): 프로젝트 독립 자기완결 플로우 스튜디오
# Usage: source lib/studio.sh && studio_init /path/to/studio "이름" "목표"
#
# 스튜디오 = 자기완결 GOLEM_PROJECT 폴더. 새 실행 엔진을 만들지 않고 기존
# agent_run/flow_create/flow_run 을 재사용한다 — 스튜디오 dir 로 cd + GOLEM_PROJECT/
# GOLEM_DIR 만 바꾸면 하네스(effort 타임아웃, 예산 가드, growth-log)가 그대로 적용된다.
#
# 규칙: jq 금지(grep/sed/awk), sed -i 금지(soul-parser.sh 의 _sed_i 사용), 원자적 쓰기
# (tmp+mv), BSD/GNU 겸용(alternation \| 미사용). agent_run/flow_create/flow_validate/
# flow_run 은 호출 시점에 참조한다(_studio_deps — bats 함수 재정의 mock 이 가능하도록
# 이미 정의돼 있으면 재소싱하지 않는다. lib/mission-loop.sh 의 _mission_loop_deps 패턴).

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${GOLEM_ROOT}/lib/json-lite.sh"
source "${GOLEM_ROOT}/lib/soul-parser.sh"

# 의존 lib 지연 로드 — 함수가 이미 정의돼 있으면(테스트 mock 포함) 재소싱하지 않는다.
# 주의: lib/flow.sh 는 내부에서 agent-runner.sh 를 무조건(source 시 매번) 재소싱한다 —
# bats 가 agent_run 을 목으로 재정의한 뒤 이 함수가 flow.sh 를 로드하면 그 목이
# 덮어써진다. studio_design 은 flow_run 이 전혀 필요 없으므로 flow_create/flow_validate
# 를 flow-dag.sh(+flow-contract.sh)만 개별 로드해 agent_run 목을 건드리지 않는다.
# flow_run 이 필요한 studio_run 은 별도의 _studio_run_deps 를 쓴다.
_studio_deps() {
  command -v flow_extract_json >/dev/null 2>&1 || source "${GOLEM_ROOT}/lib/flow-contract.sh"
  command -v flow_create       >/dev/null 2>&1 || source "${GOLEM_ROOT}/lib/flow-dag.sh"
  command -v agent_run         >/dev/null 2>&1 || source "${GOLEM_ROOT}/lib/agent-runner.sh"
}

# studio_run 전용 — flow_run(flow.sh 전용) 이 필요할 때만 flow.sh 전체를 로드한다.
_studio_run_deps() {
  _studio_deps
  command -v flow_run >/dev/null 2>&1 || source "${GOLEM_ROOT}/lib/flow.sh"
}

_STUDIO_LAST_ERROR=""

# ── dir 인자 해석 ───────────────────────────────────────────────────────────
# 첫 인자가 (존재하는 디렉토리) 또는 (경로 구분자 '/' 포함) 이면 dir 로 소비한다.
_studio_is_dir_arg() {
  local a="$1"
  [ -z "$a" ] && return 1
  [ -d "$a" ] && return 0
  case "$a" in */*) return 0 ;; esac
  return 1
}

# dir 인자를 절대 경로로 정규화. 인자가 없으면 GOLEM_PROJECT(없으면 cwd) 폴백.
_studio_dir() {
  local d="$1"
  if [ -z "$d" ]; then
    printf '%s\n' "${GOLEM_PROJECT:-$(pwd)}"
    return 0
  fi
  case "$d" in
    /*|[A-Za-z]:[\\/]*) printf '%s\n' "$d" ;;   # 이미 절대경로 (POSIX 또는 Windows 드라이브 문자)
    *)                  printf '%s/%s\n' "$(pwd)" "$d" ;;
  esac
}

# ── 1. studio_init ──────────────────────────────────────────────────────────
# studio_init [dir] [name] [goal] — 멱등 스캐폴드
studio_init() {
  local dir
  if _studio_is_dir_arg "${1:-}"; then dir=$(_studio_dir "$1"); shift; else dir=$(_studio_dir ""); fi
  local name="${1:-}" goal="${2:-}"

  mkdir -p "${dir}/.golem/souls" "${dir}/.golem/flows" "${dir}/.golem/growth-log" \
           "${dir}/.golem/mailbox" "${dir}/.golem/sessions" "${dir}/.golem/runs" \
           "${dir}/output" || {
    echo "[studio] ERROR: 디렉토리 생성 실패: ${dir}" >&2
    return 1
  }

  local sj="${dir}/studio.json"
  local existing_name="" existing_goal="" existing_created=""
  if [ -f "$sj" ]; then
    local sj_raw; sj_raw=$(tr -d '\n\r' < "$sj")
    existing_name=$(_json_unescape "$(_json_get_string "$sj_raw" name)")
    existing_goal=$(_json_unescape "$(_json_get_string "$sj_raw" goal)")
    existing_created=$(_json_scalar "$sj_raw" created)
  fi
  [ -z "$name" ] && name="$existing_name"
  [ -z "$goal" ] && goal="$existing_goal"
  local created="$existing_created"
  if [ -z "$created" ]; then
    created=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
  fi

  local name_esc goal_esc
  name_esc=$(_json_escape "$name")
  goal_esc=$(_json_escape "$goal")

  local tmp="${sj}.tmp.$$"
  printf '{"name":"%s","goal":"%s","created":"%s","version":1}' \
    "$name_esc" "$goal_esc" "$created" > "$tmp" && mv -f "$tmp" "$sj" || {
    echo "[studio] ERROR: studio.json 쓰기 실패" >&2
    return 1
  }

  # flowsmith 빌트인 SOUL 복사 — 이미 있으면 건드리지 않음(사용자 커스텀 보존)
  # 복사 실패는 init 을 죽이지 않고 WARN — studio_design 이 소환 전 재복사한다.
  local fs_dest="${dir}/.golem/souls/flowsmith.md"
  if [ ! -f "$fs_dest" ]; then
    cp "${GOLEM_ROOT}/templates/souls/flowsmith.md" "$fs_dest" 2>/dev/null || \
      echo "[studio] WARN: flowsmith 템플릿 복사 실패: ${fs_dest}" >&2
  fi

  # 레지스트리 append — 동일 path 중복 방지 (grep -F).
  # 저장 라인은 _json_escape 된 path 이므로 dedup 검색도 이스케이프된 값으로 —
  # 백슬래시 포함 Windows 경로가 init 마다 중복 append 되던 결함 방지.
  local registry="${GOLEM_ROOT}/studios.jsonl"
  local dir_esc
  dir_esc=$(_json_escape "$dir")
  if ! grep -qF "\"path\":\"${dir_esc}\"" "$registry" 2>/dev/null; then
    printf '{"name":"%s","path":"%s","registered":"%s"}\n' \
      "$name_esc" "$dir_esc" "$created" >> "$registry"
  fi

  echo "[studio] 초기화 완료: ${dir}"
  echo "  name: ${name}"
  echo "  goal: ${goal}"
  return 0
}

# ── 2. studio_agent_add ─────────────────────────────────────────────────────
# studio_agent_add [dir] <name> <model> <role> [rules]
studio_agent_add() {
  local dir
  if _studio_is_dir_arg "${1:-}"; then dir=$(_studio_dir "$1"); shift; else dir=$(_studio_dir ""); fi
  local name="${1:-}" model="${2:-sonnet}" role="${3:-}" rules="${4:-}"

  if [ -z "$name" ]; then
    echo "[studio] ERROR: Usage: studio agent-add [dir] <name> <model> <role> [rules]" >&2
    return 1
  fi
  _validate_soul_name "$name" || return 1

  local lower_name
  lower_name=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')

  local souls_dir="${dir}/.golem/souls"
  mkdir -p "$souls_dir"
  local soul_file="${souls_dir}/${lower_name}.md"
  if [ -f "$soul_file" ]; then
    echo "[studio] ERROR: 이미 존재하는 에이전트: ${lower_name}" >&2
    return 1
  fi

  # 웹/CLI 자유 텍스트가 셸 확장·frontmatter 구조를 깨지 못하게 가드
  # (unquoted heredoc 금지 — printf 인자로만 보간해 $()/백틱 확장을 원천 차단)
  case "${model}${role}${rules}" in
    *$'\n'*|*$'\r'*)
      echo "[studio] ERROR: model/role/rules 에 개행 문자를 포함할 수 없다" >&2
      return 1 ;;
  esac
  case "$model" in
    *[!a-zA-Z0-9._-]*|"")
      echo "[studio] ERROR: model 형식 오류: ${model}" >&2
      return 1 ;;
  esac

  local date
  date=$(date +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)

  # specialty 는 YAML flow-seq(`[...]`) 값이므로 role 원문에 포함된 '[' ']' ','
  # 가 시퀀스 구조를 깨거나(닫는 ']' 조기 종료) 잘못 분할(',')시킬 수 있다.
  # role: 라인은 원문 그대로 유지하고, specialty 값에서만 정화한다.
  local specialty_val
  specialty_val=$(printf '%s' "$role" | tr -d '[]' | sed 's/,/·/g')

  local tmp="${soul_file}.tmp.$$"
  {
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    printf 'role: %s\n' "$role"
    printf 'rank: novice\n'
    printf 'specialty: [%s]\n' "$specialty_val"
    printf 'model: %s\n' "$model"
    printf 'isolation: none\n'
    printf 'created: %s\n' "$date"
    printf -- '---\n\n'
    printf '%s\n' '## 프로젝트 컨텍스트 (프롬프트에 주입됨)'
    printf -- '- 역할: %s\n' "$role"
    printf '%s\n' \
      '- 기술스택: (스튜디오 목표에 맞게 설정)' \
      '- 아키텍처: (스튜디오 목표에 맞게 설정)' \
      '- 우선순위: (스튜디오 목표에 맞게 설정)' \
      '' \
      '## 전문 지식 (컨텍스트 힌트로 주입)' \
      '- (스튜디오 목표에 맞게 추가)' \
      '' \
      '## 행동 원칙' \
      '- (스튜디오 목표에 맞게 추가)'
    if [ -n "$rules" ]; then
      printf '%s\n' '' '## 규칙'
      printf -- '- %s\n' "$rules"
    fi
    printf '%s\n' '' '## 성장 기록 요약'
    printf -- '- %s: 생성 (studio agent-add)\n' "$date"
  } > "$tmp"
  mv -f "$tmp" "$soul_file" || {
    echo "[studio] ERROR: SOUL 파일 쓰기 실패" >&2
    return 1
  }

  local gl_dir="${dir}/.golem/growth-log"
  mkdir -p "$gl_dir"
  [ -f "${gl_dir}/${lower_name}.jsonl" ] || : > "${gl_dir}/${lower_name}.jsonl"

  echo "[studio] 에이전트 생성: ${soul_file}"
  return 0
}

# ── 내부: 설계 프롬프트 조립 ──────────────────────────────────────────────────
_studio_design_prompt() {
  local goal="$1"
  # goal 은 자유 텍스트 — printf 인자로만 보간(unquoted heredoc 확장 금지)
  printf '목표: %s\n\n' "$goal"
  cat <<'PROMPTEOF'
위 목표를 달성할 전문가 에이전트 팀과 실행 플로우를 설계하라.
아래 계약을 정확히 지키는 코드펜스(```json ... ```) 하나만 출력하라. 다른 텍스트는 절대 포함하지 마라.

{"agents":[{"name":"agent-slug","model":"haiku|sonnet|opus","role":"...","rules":"..."}],"steps":[{"id":"step_id","soul":"agent-slug","task":"...","deps":["이전 step id"]}]}

계약:
- agents: 2~6개, name은 [a-z0-9-]만 허용(소문자/숫자/하이픈)
- model은 haiku, sonnet, opus 중 하나만 사용
- steps는 1-depth 평면 배열이며 각 id는 [A-Za-z0-9_-]+ 형식, 배열 내 고유
- deps는 자신보다 앞서 정의된 id만 참조 (사이클 금지)
- soul 필드는 agents 에 정의한 name 중 하나를 참조
- task 문자열에 리터럴 시퀀스 "},{" 를 포함하지 말 것
- 상류 단계 출력이 필요하면 task에 {{step_id}} 형식으로 참조 가능
- 목표가 한국어면 role/rules/task도 한국어로 작성
PROMPTEOF
}

# ── 내부: JSON 문자열에서 "<key>":[...] 로 시작하는 부분 문자열 반환 ─────────
# 반환값을 _json_array_items 에 그대로 넘기면 해당 배열의 원소만 정확히 추출된다
# (그 함수는 입력 전체에서 첫 '[' 를 기준점으로 depth 를 추적하기 때문).
_studio_key_array_raw() {
  local json="$1" key="$2"
  # "<key>" 뒤에 콜론이 오는 위치에 앵커 — 필드 VALUE 가 "steps"/"agents" 인
  # 경우("task":"steps" 등) 오인 앵커 방지. key 는 정규식 메타문자 없는 고정어.
  awk -v key="$key" '
  { s = s $0 }
  END {
    if (match(s, "\"" key "\"[[:space:]]*:") == 0) { exit 1 }
    printf "%s", substr(s, RSTART)
  }' <<<"$json"
}

# ── 내부: flowsmith 출력(JSON) 계약 검증 ────────────────────────────────────
# 성공: rc=0. 실패: rc=1 + _STUDIO_LAST_ERROR 에 사유.
_studio_validate_design() {
  local json="$1"

  case "$json" in
    *'"agents"'*) : ;;
    *) _STUDIO_LAST_ERROR="JSON에 agents 키가 없습니다"; return 1 ;;
  esac
  case "$json" in
    *'"steps"'*) : ;;
    *) _STUDIO_LAST_ERROR="JSON에 steps 키가 없습니다"; return 1 ;;
  esac

  local agents_raw steps_raw
  agents_raw=$(_studio_key_array_raw "$json" agents) || true
  steps_raw=$(_studio_key_array_raw "$json" steps) || true
  [ -n "$agents_raw" ] || { _STUDIO_LAST_ERROR="agents 배열을 찾을 수 없습니다"; return 1; }
  [ -n "$steps_raw" ] || { _STUDIO_LAST_ERROR="steps 배열을 찾을 수 없습니다"; return 1; }

  local n_agents=0 item a_name a_model
  while IFS= read -r item; do
    [ -z "$item" ] && continue
    n_agents=$((n_agents + 1))
    a_name=$(_json_unescape "$(_json_get_string "$item" name)")
    a_model=$(_json_unescape "$(_json_get_string "$item" model)")
    if ! printf '%s' "$a_name" | grep -qE '^[a-z0-9-]+$'; then
      _STUDIO_LAST_ERROR="agent name 형식 위반: '${a_name}' ([a-z0-9-]만 허용)"
      return 1
    fi
    case "$a_model" in
      haiku|sonnet|opus) : ;;
      *) _STUDIO_LAST_ERROR="agent model 형식 위반: '${a_model}' (haiku|sonnet|opus 중 하나)"; return 1 ;;
    esac
  done <<EOF
$(printf '%s\n' "$agents_raw" | _json_array_items)
EOF
  if [ "$n_agents" -lt 2 ] || [ "$n_agents" -gt 6 ]; then
    _STUDIO_LAST_ERROR="agents 개수 위반: ${n_agents}건 (2~6개 필요)"
    return 1
  fi

  local n_steps=0 s_id s_task s_task_plain
  while IFS= read -r item; do
    [ -z "$item" ] && continue
    n_steps=$((n_steps + 1))
    s_id=$(_json_unescape "$(_json_get_string "$item" id)")
    s_task=$(_json_get_string "$item" task)
    if ! printf '%s' "$s_id" | grep -qE '^[A-Za-z0-9_-]+$'; then
      _STUDIO_LAST_ERROR="step id 형식 위반: '${s_id}'"
      return 1
    fi
    [ -n "$s_task" ] || { _STUDIO_LAST_ERROR="step '${s_id}' task 필드 누락"; return 1; }
    s_task_plain=$(_json_unescape "$s_task")
    case "$s_task_plain" in
      *'},{'*) _STUDIO_LAST_ERROR="step '${s_id}' task에 금지 시퀀스 '},{' 포함"; return 1 ;;
    esac
  done <<EOF
$(printf '%s\n' "$steps_raw" | _json_array_items)
EOF
  [ "$n_steps" -gt 0 ] || { _STUDIO_LAST_ERROR="steps 배열이 비어있습니다"; return 1; }

  return 0
}

# ── 3. studio_design ─────────────────────────────────────────────────────────
# studio_design [dir] "<goal>" — flowsmith 소환 → agents 생성 + flow_create
studio_design() {
  local dir
  # dir 로 소비하는 건 인자가 2개 이상일 때만 — 단일 인자는 항상 goal 이다.
  # (goal 텍스트에 '/' 가 들어 있어도 dir 로 오인하지 않게 하는 가드 —
  #  게이트웨이는 cwd=스튜디오 + GOLEM_PROJECT 로 goal 하나만 보낸다)
  if [ "$#" -ge 2 ] && _studio_is_dir_arg "${1:-}"; then dir=$(_studio_dir "$1"); shift; else dir=$(_studio_dir ""); fi
  local goal="${1:-}"

  if [ -z "$goal" ]; then
    echo "[studio] ERROR: Usage: studio design [dir] \"<goal>\"" >&2
    return 1
  fi

  [ -f "${dir}/studio.json" ] || studio_init "$dir" "" "$goal" >/dev/null

  _studio_deps

  # flowsmith SOUL 보증 — init 의 템플릿 복사가 실패했을 수 있어 소환 전 재복사.
  # 그래도 없으면 agent_run 의 모호한 실패 대신 여기서 명확한 에러로 끊는다.
  local fs_soul="${dir}/.golem/souls/flowsmith.md"
  if [ ! -f "$fs_soul" ]; then
    mkdir -p "${dir}/.golem/souls"
    cp "${GOLEM_ROOT}/templates/souls/flowsmith.md" "$fs_soul" 2>/dev/null || true
    if [ ! -f "$fs_soul" ]; then
      echo "[studio] ERROR: flowsmith SOUL 없음 (템플릿 재복사 실패): ${fs_soul}" >&2
      return 1
    fi
  fi

  local base_prompt corrective="" attempt=0 json="" err="" raw
  base_prompt=$(_studio_design_prompt "$goal")

  while :; do
    attempt=$((attempt + 1))

    raw=$(cd "$dir" && GOLEM_PROJECT="$dir" GOLEM_DIR="${dir}/.golem" \
      agent_run flowsmith "${base_prompt}${corrective}" 2>&1)

    local extracted extracted_rc
    if extracted=$(printf '%s\n' "$raw" | flow_extract_json 2>&1); then
      extracted_rc=0
    else
      extracted_rc=$?
    fi

    if [ "$extracted_rc" -eq 0 ]; then
      json=$(printf '%s' "$extracted" | tr -d '\r')
      if _studio_validate_design "$json"; then
        err=""
        break
      fi
      err="$_STUDIO_LAST_ERROR"
    else
      err="$extracted"
    fi

    if [ "$attempt" -ge 2 ]; then
      echo "[studio] ERROR: flowsmith 출력 검증 실패(재질의 후에도 실패): ${err}" >&2
      return 1
    fi

    corrective="

[수정 요청] 이전 출력이 계약을 위반했습니다: ${err}
정확한 계약을 다시 준수하여 코드펜스(\`\`\`json ... \`\`\`) 하나만 출력하라."
  done

  # ── agents 적용 (studio_agent_add 반복, 이미 존재하면 건너뜀) ──
  local agents_raw souls_created="" item a_name a_model a_role a_rules
  agents_raw=$(_studio_key_array_raw "$json" agents)
  while IFS= read -r item; do
    [ -z "$item" ] && continue
    a_name=$(_json_unescape "$(_json_get_string "$item" name)")
    a_model=$(_json_unescape "$(_json_get_string "$item" model)")
    a_role=$(_json_unescape "$(_json_get_string "$item" role)")
    a_rules=$(_json_unescape "$(_json_get_string "$item" rules)")
    if [ -f "${dir}/.golem/souls/${a_name}.md" ]; then
      souls_created="${souls_created} ${a_name}(기존)"
      continue
    fi
    if studio_agent_add "$dir" "$a_name" "$a_model" "$a_role" "$a_rules" >/dev/null; then
      souls_created="${souls_created} ${a_name}"
    fi
  done <<EOF
$(printf '%s\n' "$agents_raw" | _json_array_items)
EOF

  # ── steps 조립 → flow_create ──
  local steps_raw steps_file
  steps_raw=$(_studio_key_array_raw "$json" steps)
  mkdir -p "${dir}/.golem/flows"
  steps_file="${dir}/.golem/flows/.design-steps.$$.json"
  {
    printf '['
    local first=1
    while IFS= read -r item; do
      [ -z "$item" ] && continue
      if [ "$first" -eq 1 ]; then first=0; else printf ','; fi
      printf '%s' "$item"
    done <<EOF2
$(printf '%s\n' "$steps_raw" | _json_array_items)
EOF2
    printf ']'
  } > "$steps_file"

  local flow_id
  if ! flow_id=$(FLOW_DIR="${dir}/.golem/flows" flow_create "$goal" "$steps_file"); then
    rm -f "$steps_file"
    echo "[studio] ERROR: flow_create 실패 (steps 검증 또는 사이클 오류)" >&2
    return 1
  fi
  rm -f "$steps_file"

  echo "[studio] 설계 완료"
  echo "  agents:${souls_created}"
  echo "  flow_id: ${flow_id}"
  return 0
}

# ── 4. studio_run ────────────────────────────────────────────────────────────
# studio_run [dir] [flow_id] — 기본 flow_id = 최신(mtime) 플로우
studio_run() {
  local dir
  if _studio_is_dir_arg "${1:-}"; then dir=$(_studio_dir "$1"); shift; else dir=$(_studio_dir ""); fi
  local flow_id="${1:-}"

  _studio_run_deps

  local flows_dir="${dir}/.golem/flows"
  if [ -z "$flow_id" ]; then
    # mtime 내림차순 최신 선택 — 동률(같은 초)일 때 `ls -1t` 순서는 미정의라
    # bash 빌트인 `-nt`(외부 stat/ls 의존 없이 GNU/BSD 겸용)로 직접 비교하고,
    # 동률 시 flow_id(dirname) 사전순 최댓값을 결정적으로 고른다
    # (flow_id 는 epoch+pid 를 포함하므로 사전순 비교가 안정적인 2차 키가 된다).
    local newest="" f d1 d2 lexmax
    for f in "${flows_dir}"/*/state.json; do
      [ -f "$f" ] || continue
      if [ -z "$newest" ]; then
        newest="$f"
      elif [ "$f" -nt "$newest" ]; then
        newest="$f"
      elif [ ! "$newest" -nt "$f" ]; then
        d1=$(basename "$(dirname "$f")")
        d2=$(basename "$(dirname "$newest")")
        lexmax=$(printf '%s\n%s\n' "$d1" "$d2" | LC_ALL=C sort | tail -1)
        [ "$lexmax" = "$d1" ] && newest="$f"
      fi
    done
    if [ -z "$newest" ]; then
      echo "[studio] ERROR: 플로우가 없습니다: ${dir}" >&2
      return 1
    fi
    flow_id=$(basename "$(dirname "$newest")")
  fi

  local state="${flows_dir}/${flow_id}/state.json"
  if [ ! -f "$state" ]; then
    echo "[studio] ERROR: 플로우 없음: ${flow_id}" >&2
    return 1
  fi

  (
    cd "$dir" || exit 1
    export GOLEM_PROJECT="$dir" GOLEM_DIR="${dir}/.golem"
    # 산출물 디렉토리 계약 — flow_step_run 이 agent task 에 저장 규칙을 주입한다
    # (에이전트가 저장 경로를 사용자에게 되묻는 문제 방지)
    mkdir -p "${dir}/output"
    export GOLEM_FLOW_OUTPUT_DIR="${dir}/output"
    FLOW_DIR="${flows_dir}" flow_validate "$state" && FLOW_DIR="${flows_dir}" flow_run "$flow_id"
  )
  return $?
}

# ── 5. studio_status ─────────────────────────────────────────────────────────
# studio_status [dir]
studio_status() {
  local dir
  if _studio_is_dir_arg "${1:-}"; then dir=$(_studio_dir "$1"); shift; else dir=$(_studio_dir ""); fi

  echo "=== Studio: ${dir} ==="
  if [ -f "${dir}/studio.json" ]; then
    local sj name goal
    sj=$(tr -d '\n\r' < "${dir}/studio.json")
    name=$(_json_unescape "$(_json_get_string "$sj" name)")
    goal=$(_json_unescape "$(_json_get_string "$sj" goal)")
    echo "name: ${name}"
    echo "goal: ${goal}"
  else
    echo "(studio.json 없음 — studio init 필요)"
  fi

  echo ""
  echo "-- souls --"
  local f found=0
  for f in "${dir}/.golem/souls/"*.md; do
    [ -f "$f" ] || continue
    found=1
    basename "$f" .md
  done
  [ "$found" -eq 0 ] && echo "(없음)"

  echo ""
  echo "-- flows --"
  found=0
  for f in "${dir}/.golem/flows/"*/state.json; do
    [ -f "$f" ] || continue
    found=1
    local fid fjson fgoal fstatus
    fid=$(basename "$(dirname "$f")")
    fjson=$(tr -d '\n\r' < "$f")
    fgoal=$(_json_unescape "$(_json_get_string "$fjson" goal)")
    fstatus=$(_json_get_string "$fjson" status)
    printf '%s\t%s\t%s\n' "$fid" "${fstatus:-?}" "$fgoal"
  done
  [ "$found" -eq 0 ] && echo "(없음)"
  return 0
}

# ── 6. studio_list ───────────────────────────────────────────────────────────
# studio_list — GOLEM_ROOT/studios.jsonl 목록
studio_list() {
  local registry="${GOLEM_ROOT}/studios.jsonl"
  if [ ! -s "$registry" ]; then
    echo "등록된 스튜디오 없음"
    return 0
  fi

  echo "=== Studios ==="
  local line name path
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    name=$(_json_unescape "$(_json_get_string "$line" name)")
    path=$(_json_unescape "$(_json_get_string "$line" path)")
    printf '%-20s %s\n' "$name" "$path"
  done < "$registry"
  return 0
}
