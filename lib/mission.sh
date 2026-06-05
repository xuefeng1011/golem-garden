#!/bin/bash
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

MISSION_DIR="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/missions"

# JSON 문자열 값 추출 (escape-aware) — agent-runner.sh 의 정규식과 동일한
# `\([^"\\]\|\\.\)*` 패턴으로 이스케이프된 `\"` 를 값 내부로 올바르게 포함한다.
# quote-naive `grep -o '"key":"[^"]*"'` 가 `\"` 에서 잘리던 버그(데이터 손상)를 막는다.
# 출력은 RAW(이스케이프된) JSON 문자열 — 표시용으로는 _json_unescape 를 거친다.
# _json_get_string <json_line> <key>
_json_get_string() {
  printf '%s' "$1" | sed -n "s/.*\"$2\":\"\\(\\([^\"\\\\]\\|\\\\.\\)*\\)\".*/\\1/p"
}

# _json_escape 의 역연산 — 표시용 디코드 (\\n→개행, \\t→탭, \\\"→\", \\\\→\\)
# 순서 중요: 백슬래시 시퀀스를 먼저 해석하되 \\\\ 는 마지막에 풀어 이중 해석 방지.
# _json_unescape <raw_json_string>
_json_unescape() {
  printf '%s' "$1" | awk '
    {
      out=""
      n=length($0)
      i=1
      while (i<=n) {
        c=substr($0,i,1)
        if (c=="\\" && i<n) {
          d=substr($0,i+1,1)
          if (d=="n")      { out=out "\n"; i+=2; continue }
          else if (d=="t") { out=out "\t"; i+=2; continue }
          else if (d=="r") { out=out "\r"; i+=2; continue }
          else if (d=="\""){ out=out "\""; i+=2; continue }
          else if (d=="\\"){ out=out "\\"; i+=2; continue }
          else if (d=="/") { out=out "/";  i+=2; continue }
          else             { out=out d;    i+=2; continue }
        }
        out=out c; i++
      }
      printf "%s", out
    }'
}

# 단일 state.json scalar 필드(이스케이프 없는 id/status/created/seq 등) 추출.
# _json_scalar <json_line> <key>
_json_scalar() {
  grep -o "\"$2\":\"[^\"]*\"" <<<"$1" | head -1 | sed "s/\"$2\":\"//;s/\"$//"
}

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

  _mission_rewrite_tasks "$mdir" "$tasks_json"

  # spec.md ## 태스크 섹션을 체크리스트로 교체 (## 태스크 이후 전부 재작성)
  local spec="${mdir}/spec.md" tmp="${mdir}/spec.md.tmp"
  awk '/^## 태스크$/{print; exit} {print}' "$spec" > "$tmp"
  printf '%s' "$checklist" >> "$tmp"
  mv "$tmp" "$spec"
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
    local o_idx o_task_raw o_soul_raw o_status o_task_plain o_status_out o_soul_out
    o_idx=$(grep -o '"idx":[0-9]*' <<<"$obj" | sed 's/"idx"://')
    o_task_raw=$(_json_get_string "$obj" task)
    o_soul_raw=$(_json_get_string "$obj" soul)
    o_status=$(_json_scalar "$obj" status)
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
    local task_re soul_re
    task_re=$(_json_escape "$o_task_plain")
    soul_re=$(_json_escape "$(_json_unescape "$o_soul_out")")
    tasks_json="${tasks_json}{\"idx\":${o_idx},\"task\":\"${task_re}\",\"soul\":\"${soul_re}\",\"status\":\"${o_status_out}\"}"
  done < <(grep -o '{"idx":[0-9]*,"task":"\([^"\\]\|\\.\)*","soul":"\([^"\\]\|\\.\)*","status":"[^"]*"}' <<<"$line")
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
  done < <(grep -o '{"idx":[0-9]*,"task":"\([^"\\]\|\\.\)*","soul":"\([^"\\]\|\\.\)*","status":"[^"]*"}' "$state")
  mv "$tmp" "$spec"
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
  done < <(grep -o '{"idx":[0-9]*,"task":"\([^"\\]\|\\.\)*","soul":"\([^"\\]\|\\.\)*","status":"[^"]*"}' "$state")
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
$(grep -o '{"idx":[0-9]*,"task":"\([^"\\]\|\\.\)*","soul":"\([^"\\]\|\\.\)*","status":"[^"]*"}' "$state")
EOF

  if [ "$found" = false ]; then echo "none"; fi
  return 0
}
