#!/usr/bin/env bash
# mission.sh — `forge mission` 디스크/상태 레이어 (Kiro 스타일 미션 스펙 지속성)
# Usage: source lib/mission.sh && mission_init "<goal>" "<criteria>" "<constraints>" "<out_of_scope>"
#
# 하나의 목표를 완수까지 끌고 가는 미션의 스펙(requirements/design/tasks)을
# 디스크에 저장하여 턴/세션을 넘어 목표가 살아남게 한다.
# spec.md(사람용 Kiro 문서) + state.json(머신용 상태) 한 쌍으로 미션을 표현한다.

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# GOLEM_DIR 정규화 — agent-runner.sh 로직 미러.
# 단독 source(forge.sh 경유 아님) 시 GOLEM_DIR 이 비었거나 .golem 이 아닌
# 경로(루트 등)로 잘못 설정돼 있을 수 있어, 미션 파일이 엉뚱한 곳에 써진다.
case "${GOLEM_DIR:-}" in
  */.golem) : ;;
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
# _json_get_string / _json_unescape / _json_scalar — P3 계약 경화로
# lib/json-lite.sh 에 공용화 (flow-contract.sh 와 공유)
source "${GOLEM_ROOT}/lib/json-lite.sh"

MISSION_DIR="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/missions"

_mission_ensure_dir() {
  [ -d "$MISSION_DIR" ] || mkdir -p "$MISSION_DIR"
}

_mission_ts() {
  date -u +%Y-%m-%dT%H:%M:%S 2>/dev/null || date +%Y-%m-%dT%H:%M:%S
}

# 충돌 안전 미션 id (같은 초 내 충돌 방지 — RANDOM 접미사)
_mission_id() {
  echo "msn_$(date +%s)_${RANDOM}"
}

# 단조 증가 정렬키 — 같은 초 생성 시에도 최신 미션을 구별 (ns 우선, 폴백 RANDOM).
# state.json 의 "seq" 필드로 저장하여 mtime 초단위 동률 문제를 회피한다.
_mission_seq() {
  local ns
  ns=$(date +%s%N 2>/dev/null)
  case "$ns" in
    *N|"") echo "$(date +%s)$(printf '%05d' $((RANDOM % 100000)))" ;;
    *) echo "$ns" ;;
  esac
}

# id → 미션 디렉토리 경로 (없으면 빈 문자열). id 검증으로 경로 순회 차단.
_mission_resolve() {
  local id="$1"
  case "$id" in
    msn_*) : ;;
    *) echo ""; return ;;
  esac
  case "$id" in
    */*|*..*) echo ""; return ;;
  esac
  if [ -d "${MISSION_DIR}/${id}" ]; then
    echo "${MISSION_DIR}/${id}"
  else
    echo ""
  fi
}

# seq 내림차순으로 미션 디렉토리 나열 (glob 기반, ls 파이프 회피).
# seq 는 단조 증가 → 같은 초 생성도 정확히 최신순 정렬.
_mission_dirs_recent() {
  local d
  for d in "${MISSION_DIR}"/msn_*; do
    [ -d "$d" ] || continue
    local sq
    sq=$(grep -o '"seq":"[^"]*"' "${d}/state.json" 2>/dev/null | head -1 | sed 's/"seq":"//;s/"//')
    [ -z "$sq" ] && sq=0
    printf '%s\t%s\n' "$sq" "$d"
  done | sort -rn | cut -f2-
}

_mission_latest_active() {
  local d latest=""
  while IFS= read -r d; do
    [ -d "$d" ] || continue
    local st
    st=$(grep -o '"status":"[^"]*"' "${d}/state.json" 2>/dev/null | head -1 | sed 's/"status":"//;s/"//')
    if [ "$st" = "active" ]; then latest=$(basename "$d"); break; fi
  done <<EOF
$(_mission_dirs_recent)
EOF
  echo "$latest"
}

# mission_init <goal> <criteria> <constraints> <out_of_scope> → id 를 stdout 에 echo
mission_init() {
  local goal="$1" criteria="$2" constraints="$3" out_of_scope="$4"
  _mission_ensure_dir

  local id ts seq
  id=$(_mission_id)
  ts=$(_mission_ts)
  seq=$(_mission_seq)
  local mdir="${MISSION_DIR}/${id}"
  mkdir -p "$mdir"

  cat > "${mdir}/spec.md" <<SPECEOF
# Mission: ${goal}

> id: ${id} · created: ${ts}

## 목표
${goal}

## 성공 기준
${criteria}

## 제약·범위
${constraints}

## 비범위
${out_of_scope}

## 태스크
(아직 분해되지 않음 — \`mission set-tasks\` 로 등록)
SPECEOF

  local g_esc
  g_esc=$(_json_escape "$goal")
  cat > "${mdir}/state.json" <<STATEEOF
{"id":"${id}","goal":"${g_esc}","status":"active","created":"${ts}","seq":"${seq}","tasks":[]}
STATEEOF

  echo "$id"
}

# 태스크 배열(JSON) 만 교체하여 state.json 재작성
# _mission_rewrite_tasks <mdir> <tasks_json_array>
_mission_rewrite_tasks() {
  local mdir="$1" tasks="$2"
  local line id goal status created seq tmp
  line=$(head -1 "${mdir}/state.json")
  # goal 은 escape-aware 추출 (이미 _json_escape 된 RAW 값 — 그대로 재기록).
  # 나머지 id/status/created/seq 는 이스케이프 없는 scalar.
  id=$(_json_scalar "$line" id)
  goal=$(_json_get_string "$line" goal)
  status=$(_json_scalar "$line" status)
  created=$(_json_scalar "$line" created)
  seq=$(_json_scalar "$line" seq)
  tmp="${mdir}/state.json.tmp"
  cat > "$tmp" <<STATEEOF
{"id":"${id}","goal":"${goal}","status":"${status}","created":"${created}","seq":"${seq}","tasks":${tasks}}
STATEEOF
  mv "$tmp" "${mdir}/state.json"
}

# mission_set_tasks <id> "<t1>|<t2>|<t3>"
mission_set_tasks() {
  local id="$1" raw="$2"
  local mdir
  mdir=$(_mission_resolve "$id")
  if [ -z "$mdir" ]; then echo "[mission] ERROR: 미션 없음: ${id}" >&2; return 1; fi
  if [ -z "$raw" ]; then echo "[mission] ERROR: 태스크가 비었습니다" >&2; return 1; fi

  local tasks_json="[" first=true idx=0 t t_esc
  local checklist=""
  local OLD_IFS="$IFS"
  IFS='|'
  for t in $raw; do
    IFS="$OLD_IFS"
    # 앞뒤 공백 제거
    t="${t#"${t%%[![:space:]]*}"}"
    t="${t%"${t##*[![:space:]]}"}"
    [ -z "$t" ] && { IFS='|'; continue; }
    t_esc=$(_json_escape "$t")
    if [ "$first" = true ]; then first=false; else tasks_json="${tasks_json},"; fi
    tasks_json="${tasks_json}{\"idx\":${idx},\"task\":\"${t_esc}\",\"soul\":\"\",\"status\":\"pending\"}"
    checklist="${checklist}- [ ] ${t}
"
    idx=$((idx + 1))
    IFS='|'
  done
  IFS="$OLD_IFS"
  tasks_json="${tasks_json}]"

  _mission_tasks_commit "$mdir" "$tasks_json" "$checklist"
}

# tasks 배열 + spec.md 체크리스트 확정 쓰기 (set-tasks / set-tasks-json 공용)
# _mission_tasks_commit <mdir> <tasks_json> <checklist>
_mission_tasks_commit() {
  local mdir="$1" tasks_json="$2" checklist="$3"
  _mission_rewrite_tasks "$mdir" "$tasks_json"
  # spec.md ## 태스크 섹션을 체크리스트로 교체 (## 태스크 이후 전부 재작성)
  local spec="${mdir}/spec.md" tmp="${mdir}/spec.md.tmp"
  awk '/^## 태스크$/{print; exit} {print}' "$spec" > "$tmp"
  printf '%s' "$checklist" >> "$tmp"
  mv "$tmp" "$spec"
}

# [승격] _mission_json_array_items 본체는 lib/json-lite.sh 의 _json_array_items 로
# 이동(P3 공용화 — studio.sh 도 동일 워커를 재사용). 이 별칭은 back-compat 유지용.
_mission_json_array_items() { _json_array_items "$@"; }

# mission_set_tasks_json <id> <json_or_file>
# Nex 분해 JSON 계약(P1-2) 브릿지 — 두 형태 수용:
#   ["태스크1","태스크2"]  또는  [{"task":"태스크1",...},...] (task 외 필드 무시)
# 파이프(|)·이스케이프 따옴표가 든 태스크도 안전하게 round-trip 된다.
mission_set_tasks_json() {
  local id="$1" src="$2"
  local mdir
  mdir=$(_mission_resolve "$id")
  if [ -z "$mdir" ]; then echo "[mission] ERROR: 미션 없음: ${id}" >&2; return 1; fi
  if [ -z "$src" ]; then echo "[mission] ERROR: JSON 이 비었습니다" >&2; return 1; fi

  local json
  if [ -f "$src" ]; then json=$(cat "$src"); else json="$src"; fi

  local line task_raw task t_esc rubric_items rubric_field
  local tasks_json="[" first=true idx=0 checklist=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    rubric_field=""
    case "$line" in
      '{'*)
        task_raw=$(_json_get_string "$line" task)
        # B-5: step 객체에 rubric 배열이 있으면 함께 보존 (없으면 키 자체 생략)
        rubric_items=$(_json_get_string_array "$line" rubric)
        if [ -n "$rubric_items" ]; then
          rubric_field=",\"rubric\":\"$(_json_escape "$rubric_items")\""
        fi
        ;;
      '"'*) task_raw="${line#\"}"; task_raw="${task_raw%\"}" ;;
      *) continue ;;
    esac
    [ -z "$task_raw" ] && continue
    # task_raw 는 RAW(이스케이프된) JSON 문자열 — plain 으로 디코드 후 재이스케이프
    task=$(_json_unescape "$task_raw")
    t_esc=$(_json_escape "$task")
    if [ "$first" = true ]; then first=false; else tasks_json="${tasks_json},"; fi
    tasks_json="${tasks_json}{\"idx\":${idx},\"task\":\"${t_esc}\",\"soul\":\"\",\"status\":\"pending\"${rubric_field}}"
    checklist="${checklist}- [ ] $(printf '%s' "$task" | tr '\n' ' ')
"
    idx=$((idx + 1))
  done <<EOF
$(printf '%s\n' "$json" | _mission_json_array_items)
EOF

  if [ "$idx" -eq 0 ]; then
    echo "[mission] ERROR: JSON 에서 태스크를 찾지 못했습니다 (배열/task 필드 확인)" >&2
    return 1
  fi
  tasks_json="${tasks_json}]"

  _mission_tasks_commit "$mdir" "$tasks_json" "$checklist"
  echo "[mission] 태스크 ${idx}건 등록 (JSON)"
}

# mission_task <id> <idx> <status> [soul]
# status: pending|in_progress|done|failed
mission_task() {
  local id="$1" idx="$2" status="$3" soul="${4:-}"
  local mdir
  mdir=$(_mission_resolve "$id")
  if [ -z "$mdir" ]; then echo "[mission] ERROR: 미션 없음: ${id}" >&2; return 1; fi
  # idx 는 반드시 음이 아닌 정수 — 비정수 idx 가 grep/sed 정규식·JSON 으로
  # 흘러들어가 state.json 을 손상시키던 버그(예: '0\|1', '.*')를 차단한다.
  case "$idx" in
    ''|*[!0-9]*) echo "[mission] ERROR: idx must be a non-negative integer: ${idx}" >&2; return 1 ;;
  esac
  case "$status" in
    pending|in_progress|done|failed) : ;;
    *) echo "[mission] ERROR: 잘못된 status: ${status}" >&2; return 1 ;;
  esac

  local state="${mdir}/state.json"
  local line
  line=$(head -1 "$state")

  # 대상 idx 존재 확인 (grep -o 로 객체 추출 — 매칭 여부만 검사).
  if [ -z "$(grep -o "{\"idx\":${idx},[^}]*}" <<<"$line" | head -1)" ]; then
    echo "[mission] ERROR: 태스크 idx 없음: ${idx}" >&2; return 1
  fi

  local soul_esc=""
  [ -n "$soul" ] && soul_esc=$(_json_escape "$soul")

  # 렌더된 JSON 에 sed 치환을 가하는 대신 태스크 배열을 통째로 재구성한다
  # (set-tasks/_mission_rewrite_tasks 의 안전 패턴 미러). 각 객체를 escape-aware
  # 로 디코드 → 대상 idx 의 status(+soul)만 바꿔 _json_escape 로 재방출.
  # 이로써 따옴표/슬래시/이스케이프가 포함된 task/goal 이 안전하게 round-trip 된다.
  local tasks_json="[" first=true obj
  local checklist=""
  while IFS= read -r obj; do
    [ -z "$obj" ] && continue
    local o_idx o_task_raw o_soul_raw o_status o_task_plain o_status_out o_soul_out o_rubric_raw
    o_idx=$(grep -o '"idx":[0-9]*' <<<"$obj" | sed 's/"idx"://')
    o_task_raw=$(_json_get_string "$obj" task)
    o_soul_raw=$(_json_get_string "$obj" soul)
    o_status=$(_json_scalar "$obj" status)
    # B-5: rubric 은 idx/status 대상이 아니어도 그대로 보존해야 한다 —
    # 빼먹으면 status 갱신 1회마다 rubric 이 증발한다 (원본 설계 §2 경고).
    o_rubric_raw=$(_json_get_string "$obj" rubric)
    o_task_plain=$(_json_unescape "$o_task_raw")
    if [ "$o_idx" = "$idx" ]; then
      o_status_out="$status"
      if [ -n "$soul" ]; then o_soul_out="$soul_esc"; else o_soul_out="$o_soul_raw"; fi
    else
      o_status_out="$o_status"
      o_soul_out="$o_soul_raw"
    fi
    if [ "$first" = true ]; then first=false; else tasks_json="${tasks_json},"; fi
    # task/soul 은 이미 RAW(이스케이프된) 값 — _json_escape 재적용 시 이중
    # 이스케이프되므로 디코드한 plain 값을 다시 _json_escape 한다.
    local task_re soul_re rubric_field=""
    task_re=$(_json_escape "$o_task_plain")
    soul_re=$(_json_escape "$(_json_unescape "$o_soul_out")")
    if [ -n "$o_rubric_raw" ]; then
      rubric_field=",\"rubric\":\"$(_json_escape "$(_json_unescape "$o_rubric_raw")")\""
    fi
    tasks_json="${tasks_json}{\"idx\":${o_idx},\"task\":\"${task_re}\",\"soul\":\"${soul_re}\",\"status\":\"${o_status_out}\"${rubric_field}}"
  done < <(grep -oE '\{"idx":[0-9]+,"task":"([^"\\]|\\.)*","soul":"([^"\\]|\\.)*","status":"[^"]*"(,"rubric":"([^"\\]|\\.)*")?\}' <<<"$line")
  tasks_json="${tasks_json}]"

  _mission_rewrite_tasks "$mdir" "$tasks_json"

  # spec.md ## 태스크 섹션을 체크리스트로 재구성 (set-tasks 와 동일 패턴).
  # 타깃 sed 치환(데이터에 &,\,/ 포함 시 깨짐) 대신 배열 기준 전체 재작성.
  local spec="${mdir}/spec.md" tmp="${mdir}/spec.md.tmp"
  awk '/^## 태스크$/{print; exit} {print}' "$spec" > "$tmp"
  while IFS= read -r obj; do
    [ -z "$obj" ] && continue
    local o_status o_task_raw o_task_plain mark
    o_status=$(_json_scalar "$obj" status)
    o_task_raw=$(_json_get_string "$obj" task)
    o_task_plain=$(_json_unescape "$o_task_raw" | sed 's/\\n/ /g')
    mark="[ ]"
    [ "$o_status" = "done" ] && mark="[x]"
    printf -- '- %s %s\n' "$mark" "$o_task_plain" >> "$tmp"
  done < <(grep -oE '\{"idx":[0-9]+,"task":"([^"\\]|\\.)*","soul":"([^"\\]|\\.)*","status":"[^"]*"(,"rubric":"([^"\\]|\\.)*")?\}' "$state")
  mv "$tmp" "$spec"
}

# mission_task_rubric <id> <idx> — B-5 사전 계약 rubric 조회.
# state.json 에서 해당 idx 객체를 찾아 rubric 항목을 항목 1개=1줄로 낸다.
# 부재(레거시 태스크 포함) 시 빈 출력 + return 0.
mission_task_rubric() {
  local id="$1" idx="$2"
  local mdir
  mdir=$(_mission_resolve "$id")
  [ -z "$mdir" ] && return 0
  case "$idx" in
    ''|*[!0-9]*) return 0 ;;
  esac

  local state="${mdir}/state.json"
  [ -f "$state" ] || return 0
  local line obj
  line=$(head -1 "$state")

  obj=$(grep -oE '\{"idx":'"${idx}"',"task":"([^"\\]|\\.)*","soul":"([^"\\]|\\.)*","status":"[^"]*"(,"rubric":"([^"\\]|\\.)*")?\}' <<<"$line" | head -1)
  [ -z "$obj" ] && return 0

  local o_rubric_raw
  o_rubric_raw=$(_json_get_string "$obj" rubric)
  [ -z "$o_rubric_raw" ] && return 0

  _json_unescape "$o_rubric_raw"
}

# 태스크 진행도 n/m 계산 → stdout "done total"
_mission_progress() {
  local state="$1"
  local total ndone
  total=$(grep -o '"idx":[0-9]*' "$state" | wc -l | tr -d ' ')
  ndone=$(grep -o '"status":"done"' "$state" | wc -l | tr -d ' ')
  echo "${ndone} ${total}"
}

# mission_status [id] — id 있으면 해당 미션, 없으면 최근 active
mission_status() {
  _mission_ensure_dir
  local id="${1:-}"
  [ -z "$id" ] && id=$(_mission_latest_active)
  if [ -z "$id" ]; then echo "[mission] active 미션 없음"; return 1; fi
  local mdir
  mdir=$(_mission_resolve "$id")
  if [ -z "$mdir" ]; then echo "[mission] ERROR: 미션 없음: ${id}" >&2; return 1; fi

  cat "${mdir}/spec.md"
  echo ""
  echo "── 태스크 상태 ──"
  local state="${mdir}/state.json"
  while IFS= read -r obj; do
    [ -z "$obj" ] && continue
    local i tk sl st
    i=$(printf '%s' "$obj" | grep -o '"idx":[0-9]*' | sed 's/"idx"://')
    tk=$(_json_unescape "$(_json_get_string "$obj" task)")
    sl=$(_json_unescape "$(_json_get_string "$obj" soul)")
    st=$(_json_scalar "$obj" status)
    [ -z "$sl" ] && sl="-"
    printf "  [%s] %-10s %-12s %s\n" "$i" "$st" "$sl" "$tk"
  done < <(grep -oE '\{"idx":[0-9]+,"task":"([^"\\]|\\.)*","soul":"([^"\\]|\\.)*","status":"[^"]*"(,"rubric":"([^"\\]|\\.)*")?\}' "$state")
  local prog
  prog=$(_mission_progress "$state")
  echo "  진행도: ${prog% *}/${prog#* }"
}

# mission_list — 모든 미션 나열 (id, goal, status, n/m)
mission_list() {
  _mission_ensure_dir
  echo "=== GolemGarden Missions ==="
  echo ""
  printf "%-26s %-10s %-7s %s\n" "ID" "Status" "Tasks" "Goal"
  printf "%-26s %-10s %-7s %s\n" "--" "------" "-----" "----"
  local d
  while IFS= read -r d; do
    [ -d "$d" ] || continue
    local state="${d}/state.json"
    [ -f "$state" ] || continue
    local id goal status prog
    id=$(basename "$d")
    goal=$(_json_unescape "$(_json_get_string "$(head -1 "$state")" goal)" | cut -c1-40)
    status=$(_json_scalar "$(head -1 "$state")" status)
    prog=$(_mission_progress "$state")
    printf "%-26s %-10s %-7s %s\n" "$id" "$status" "${prog% *}/${prog#* }" "$goal"
  done <<EOF
$(_mission_dirs_recent)
EOF
}

# mission_complete <id> — 검증 후 orchestration 레이어가 호출
mission_complete() {
  local id="$1"
  local mdir
  mdir=$(_mission_resolve "$id")
  if [ -z "$mdir" ]; then echo "[mission] ERROR: 미션 없음: ${id}" >&2; return 1; fi
  # 원자적 치환 (tmp+mv) — 인터럽트 시에도 state.json 유효 보장.
  local st_tmp="${mdir}/state.json.tmp"
  sed 's/"status":"active"/"status":"completed"/' "${mdir}/state.json" > "$st_tmp" && mv "$st_tmp" "${mdir}/state.json"
  echo "[mission] 미션 완료: ${id}"
}

# mission_next <id> — pending 상태인 첫 번째 태스크를 'idx\ttext' 형식으로 출력.
# pending 없으면 정확히 'none', 미션 없으면 stderr 에러 + return 1.
mission_next() {
  local id="$1"
  local mdir
  mdir=$(_mission_resolve "$id")
  if [ -z "$mdir" ]; then echo "[mission] ERROR: 미션 없음: ${id}" >&2; return 1; fi

  local state="${mdir}/state.json"
  local found=false obj

  while IFS= read -r obj; do
    [ -z "$obj" ] && continue
    local st
    st=$(_json_scalar "$obj" status)
    if [ "$st" = "pending" ]; then
      local i tk
      i=$(printf '%s' "$obj" | grep -o '"idx":[0-9]*' | sed 's/"idx"://')
      tk=$(_json_unescape "$(_json_get_string "$obj" task)")
      printf '%s\t%s\n' "$i" "$tk"
      found=true
      break
    fi
  done <<EOF
$(grep -oE '\{"idx":[0-9]+,"task":"([^"\\]|\\.)*","soul":"([^"\\]|\\.)*","status":"[^"]*"(,"rubric":"([^"\\]|\\.)*")?\}' "$state")
EOF

  if [ "$found" = false ]; then echo "none"; fi
  return 0
}
