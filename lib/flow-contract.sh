#!/usr/bin/env bash
# flow-contract.sh — Nex 분해 JSON 계약 파서 헬퍼
# Usage: source lib/flow-contract.sh
# 의존: sed, awk, grep (jq 불사용) + lib/json-lite.sh (escape-aware 파서)
# 컨벤션: lib/soul-parser.sh 준수 (_sed_i, _json_escape 패턴 동일)

_FC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${_FC_ROOT}/lib/json-lite.sh"

# ── 내부 유틸 ─────────────────────────────────────────────────────────────

# 플랫폼 호환 sed -i 래퍼 (GNU/BSD 대응) — soul-parser.sh와 동일 패턴
_fc_sed_i() {
  if sed --version 2>/dev/null | grep -q 'GNU'; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

# JSON 문자열에서 키 값 추출 (단순 1depth, 중첩 객체 미지원)
# 사용: _fc_get_field "soul" '{"soul":"ryn","task":"..."}'
# P3 경화: quote-naive grep 이 값 내부의 이스케이프된 `\"` 에서 잘리던
# 취약점을 json-lite 의 escape-aware 워커로 교체 (mission.sh 와 동일 강건성).
# 출력은 RAW(이스케이프된) 값 — 기존 반환 의미 유지.
_fc_get_field() {
  local key="$1"
  local json="$2"
  local val
  val=$(_json_get_string "$json" "$key")
  # exact `"key":"` 미매칭(공백 포함 비정규화 입력) 시 구 naive 패턴 폴백
  # (BSD grep 은 BRE \| 알터네이션 미지원 — escape-aware 는 1차 경로 담당)
  if [ -z "$val" ]; then
    val=$(printf '%s' "$json" \
      | grep -o "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
      | head -1 | sed "s/^\"${key}\"[[:space:]]*:[[:space:]]*\"//;s/\"$//")
  fi
  # 문자열 매칭 실패 시 비따옴표 스칼라(숫자/불리언) 폴백 — "retry":1 등
  if [ -z "$val" ]; then
    val=$(printf '%s' "$json" \
      | grep -o "\"${key}\"[[:space:]]*:[[:space:]]*[^,}\"[:space:]]\{1,\}" \
      | sed 's/.*:[[:space:]]*//')
  fi
  printf '%s' "$val"
}

# deps 배열 추출: ["s1","s2"] → "s1 s2" (공백 구분)
_fc_get_deps() {
  local json="$1"
  printf '%s' "$json" \
    | grep -o '"deps"[[:space:]]*:[[:space:]]*\[[^]]*\]' \
    | sed 's/"deps"[[:space:]]*:[[:space:]]*\[//;s/\]//' \
    | tr -d '"' | tr ',' ' ' | tr -s ' '
}

# rubric 배열 추출 (B-5) — _json_get_string_array 의 얇은 래퍼.
# FLOW_CONTRACT §1.1 파서 제약(대괄호 [ ], 리터럴 "," 금지) 위반 항목이
# 하나라도 있으면 필드 전체를 폐기(WARN, step 은 생존) — 관대 소비 원칙.
# 출력: 항목 1개=1줄(unescape 완료). 부재/위반 시 빈 출력 + return 0.
# _fc_get_rubric <step_json_line>
_fc_get_rubric() {
  local json="$1"
  local items
  items=$(_json_get_string_array "$json" "rubric")
  [ -z "$items" ] && return 0

  local item
  while IFS= read -r item; do
    [ -z "$item" ] && continue
    case "$item" in
      *'['*|*']'*|*'","'*|*'},{'*)
        # `},{` 는 _fc_steps_lines 파편 감지가 상류에서 잡아주지만, 여기서도
        # 명시 거부해 Pydantic(_BRACE_SPLIT_RE)과 계약을 코드로 미러한다 (Zen P2 B5-1)
        echo "[WARN] _fc_get_rubric: rubric 항목이 파서 제약(FLOW_CONTRACT §1.1) 위반 — 필드 전체 폐기: ${item}" >&2
        return 0
        ;;
    esac
  done <<EOF
$items
EOF

  printf '%s\n' "$items"
}

# ── 공개 API ──────────────────────────────────────────────────────────────

# flow_extract_json — stdin 또는 파일에서 JSON 추출 (FLOW_CONTRACT v1)
# 추출 우선순위(B-4 설계 1-B): ① ```json 코드펜스 블록(첫 번째, 레거시/멀티라인 호환)
# → ② 코드펜스 없으면 마지막 `{` 로 시작하는 줄(v1 앵커 — Director가 분석/서술
# 뒤 컴팩트 JSON 한 줄만 남기는 출력 계약, FLOW_CONTRACT.md §1/§3)
# 출력: JSON 텍스트 (stdout), 둘 다 없으면 비-0 종료 + stderr
flow_extract_json() {
  local input
  if [ -n "$1" ] && [ -f "$1" ]; then
    input=$(cat "$1")
  else
    input=$(cat)
  fi

  # ① ```json ... ``` 블록 추출 (awk, 첫 번째 블록만)
  local json
  json=$(printf '%s\n' "$input" | awk '
    /^```json[[:space:]]*$/ { in_block=1; next }
    in_block && /^```[[:space:]]*$/ { exit }
    in_block { print }
  ')

  if [ -n "$json" ]; then
    printf '%s\n' "$json"
    return 0
  fi

  # ② 폴백: 마지막 `{` 또는 `[` 로 시작하는 줄 1줄 채택 (선행 공백 무시)
  # `[` 허용은 triage.sh T2 추출과의 정합 — Director 가 규격 외 배열로 응답해도
  # 두 경로가 같은 줄을 뽑는다 (Zen P1 리뷰 정합성 지적)
  local last_line
  last_line=$(printf '%s\n' "$input" | awk '
    { line = $0; sub(/^[ \t]+/, "", line); if (line ~ /^\{/ || line ~ /^\[/) last = line }
    END { if (last != "") print last }
  ')

  if [ -n "$last_line" ]; then
    printf '%s\n' "$last_line"
    return 0
  fi

  echo "[ERROR] flow_extract_json: JSON 코드펜스 또는 마지막 줄 JSON을 찾을 수 없습니다" >&2
  return 1
}

# flow_steps_array — {"steps":[...]} 텍스트를 배열([...])로 언랩 (B-4 설계 1-B ③-mission)
# mission_set_tasks_json 은 배열만 수용하므로 flow_extract_json 출력을 여기 통과시켜
# `forge mission set-tasks-json {id} -` 로 직결한다.
# 입력: stdin (컴팩트 단일 줄 전제 — flow_extract_json 출력, 멀티라인이 와도 개행 제거 후 처리)
# 출력: JSON 배열 (stdout) — 이미 배열([...]) 형태로 오면 그대로 통과
flow_steps_array() {
  local json
  json=$(cat | tr -d '\n\r')

  case "$json" in
    [[:space:]]*) json="${json#"${json%%[![:space:]]*}"}" ;;
  esac

  case "$json" in
    '{'*'"steps"'*)
      printf '%s\n' "$json" | awk '
        {
          pos = index($0, "\"steps\"")
          if (pos == 0) exit 1
          rest = substr($0, pos)
          open = index(rest, "[")
          if (open == 0) exit 1
          depth = 0; out = ""
          for (i = open; i <= length(rest); i++) {
            c = substr(rest, i, 1)
            out = out c
            if (c == "[") depth++
            else if (c == "]") { depth--; if (depth == 0) break }
          }
          print out
        }
      ' || { echo "[ERROR] flow_steps_array: steps 배열 추출 실패" >&2; return 1; }
      ;;
    '['*)
      printf '%s\n' "$json"
      ;;
    *)
      echo "[ERROR] flow_steps_array: {\"steps\":[...]} 또는 배열([...]) 형식이 아닙니다" >&2
      return 1
      ;;
  esac
}

# _fc_steps_lines — steps 배열을 step 객체 1개=1줄로 정규화해 출력
# 입력: stdin (JSON 텍스트 — 컴팩트/멀티라인 무관)
# 출력: 한 줄에 step 객체 하나 ({...}), steps 없으면 비-0
# 전제: step 객체는 1depth (내부 배열은 deps뿐, 중첩 객체 없음)
_fc_steps_lines() {
  local json
  json=$(cat | tr -d '\n\r')

  # 관용: 베어 배열([{...},...])이 오면 {"steps":...}로 감싸 처리
  case "$json" in
    [[:space:]]*) json="${json#"${json%%[![:space:]]*}"}" ;;
  esac
  case "$json" in
    '['*) json="{\"steps\":${json}}" ;;
  esac

  # "steps":[ 의 [부터 대응되는 ]까지 깊이 추적으로 내용만 추출 (단일 라인 전제)
  local steps_raw
  steps_raw=$(printf '%s\n' "$json" | awk '
    {
      pos = index($0, "\"steps\"")
      if (pos == 0) exit 1
      rest = substr($0, pos)
      open = index(rest, "[")
      if (open == 0) exit 1
      depth = 0; out = ""
      for (i = open; i <= length(rest); i++) {
        c = substr(rest, i, 1)
        if (c == "[") { depth++; if (depth == 1) continue }
        if (c == "]") { depth--; if (depth == 0) break }
        out = out c
      }
      print out
    }
  ') || return 1

  [ -n "$steps_raw" ] || return 1

  # 객체 경계 },{ 에서 분리 — [명시적 1-depth 계약] step 값(task 등)에
  # 리터럴 `},{` 가 포함되면 오분할된다. 이 경계는 flow_validate_steps 가
  # 지키는 스키마 전제이며, escape 로도 방어 불가한 문자열 부분매칭 한계.
  # 데이터 의존 없는 안전 경로가 필요하면 mission.sh 의
  # _mission_json_array_items(문자 단위 워커)를 사용하라.
  # + 키-값 경계 공백 정규화("key" : val → "key":val) — 따옴표 앵커라 값 내부 콜론은 보존
  printf '%s\n' "$steps_raw" | sed 's/},[[:space:]]*{/}\n{/g' \
    | sed 's/"[[:space:]]*:[[:space:]]*"/":"/g;
           s/"[[:space:]]*:[[:space:]]*\[/":[/g;
           s/"[[:space:]]*:[[:space:]]*\(true\|false\)/":\1/g;
           s/"[[:space:]]*:[[:space:]]*\([0-9]\)/":\1/g;
           s/^{[[:space:]]*/{/; s/[[:space:]]*}$/}/'
}

# flow_parse_steps — steps 배열에서 레코드 추출
# 입력: stdin (JSON 텍스트)
# 출력: 탭 구분 레코드 "id\tsoul\ttask\tdeps" (한 줄 = 한 step)
# 전제: steps 배열 1depth, 각 step이 단일 줄 또는 멀티줄 객체
flow_parse_steps() {
  local steps_lines
  steps_lines=$(_fc_steps_lines)

  if [ -z "$steps_lines" ]; then
    echo "[ERROR] flow_parse_steps: steps 배열을 찾을 수 없습니다" >&2
    return 1
  fi

  printf '%s\n' "$steps_lines" | while IFS= read -r block; do
    # 비어있는 블록 건너뜀
    [ -z "$(printf '%s' "$block" | tr -d '[:space:]{}')" ] && continue

    local id soul task deps
    id=$(_fc_get_field "id" "$block")
    soul=$(_fc_get_field "soul" "$block")
    task=$(_fc_get_field "task" "$block")
    deps=$(_fc_get_deps "$block")

    # id 또는 task 없으면 건너뜀
    [ -z "$id" ] && continue
    [ -z "$task" ] && continue

    # 구분자: US(0x1f) — 탭은 IFS 공백이라 빈 필드(soul="")가 접혀 필드가 밀린다
    printf '%s\037%s\037%s\037%s\n' "$id" "$soul" "$task" "$deps"
  done
}

# flow_validate_steps — steps JSON 구조 검증
# 입력: stdin (JSON 텍스트)
# 출력: 0=유효 / 비-0=위반 + stderr에 사유
flow_validate_steps() {
  local json
  json=$(cat)

  local errors=0

  # steps 파싱
  local parsed
  parsed=$(printf '%s\n' "$json" | flow_parse_steps 2>/dev/null)
  if [ $? -ne 0 ] || [ -z "$parsed" ]; then
    echo "[ERROR] flow_validate_steps: steps 배열 파싱 실패 또는 비어있음" >&2
    return 1
  fi

  # 유효 id 목록 수집
  local valid_ids=""
  while IFS=$'\037' read -r id soul task deps; do
    valid_ids="${valid_ids} ${id}"
  done <<EOF
$parsed
EOF

  # id 중복 검사 — gateway Pydantic(FlowWriteRequest)과 판정 정렬 (교차 계약,
  # tests/golden/flow-cases). 중복 id 는 상태 갱신이 첫 매칭에만 적용돼 조용한
  # 데이터 손상으로 이어진다.
  local dup
  dup=$(printf '%s\n' "$parsed" | cut -d"$(printf '\037')" -f1 | sort | uniq -d | head -1)
  if [ -n "$dup" ]; then
    echo "[ERROR] flow_validate_steps: 중복 step id '${dup}'" >&2
    errors=$((errors + 1))
  fi

  # 파편 감지 프리패스 + on_fail goto 대상 존재 검사 (단일 루프, HIGH-3/MED-5)
  # _fc_steps_lines 의 },{ 분리는 task 값 안에 리터럴 `},{` 가 있으면 오분할되고,
  # flow_parse_steps 는 id/task 없는 파편을 조용히 버려(161행) 검증이 데이터
  # 손상을 못 보고 지나칠 수 있다. 원시 블록 각각이 (a) { 로 시작 (b) } 로 끝
  # (c) "id": 포함 — 셋 중 하나라도 어기면 파편으로 간주한다.
  local raw_lines
  raw_lines=$(printf '%s\n' "$json" | _fc_steps_lines 2>/dev/null)
  if [ -n "$raw_lines" ]; then
    # IFS 미지정 read: 기본 IFS(공백/탭/개행)가 선행/후행 공백을 트림한다.
    # _fc_steps_lines 첫 블록에 남는 들여쓰기 공백이 '{' 시작 판정을 오탐시키던 버그 수정.
    while read -r raw_block; do
      [ -z "$(printf '%s' "$raw_block" | tr -d '[:space:]{}')" ] && continue

      local frag_bad=0
      case "$raw_block" in
        \{*) : ;;
        *) frag_bad=1 ;;
      esac
      case "$raw_block" in
        *\}) : ;;
        *) frag_bad=1 ;;
      esac
      # 부분문자열 검사라 극단적으로 손상된 JSON(예: id 키 자체가 잘려나간
      # 파편)에서는 이론상 false negative 가 가능하다. 그래도 이 검사를
      # 유지하는 이유: (1) tests/golden/flow-cases 가 실제 손상 패턴을
      # 커버하고, (2) 이후 Pydantic 스키마 검증이 필수 필드 누락을 이중으로
      # 잡아내는 방어선이라 여기서는 흔한 케이스만 저비용으로 걸러도 충분하다.
      case "$raw_block" in
        *'"id":'*) : ;;
        *) frag_bad=1 ;;
      esac

      if [ "$frag_bad" -eq 1 ]; then
        echo "[ERROR] flow_validate_steps: step 객체 파편 감지 — task 값에 },{ 포함 의심 (1-depth 계약 위반)" >&2
        errors=$((errors + 1))
        continue
      fi

      # rubric 제약 위반은 WARN + 필드 폐기(step 생존) — errors 에 가산하지 않는다.
      # _fc_get_rubric 자체가 위반 시 WARN 을 stderr 로 내고 빈 출력만 낸다.
      _fc_get_rubric "$raw_block" >/dev/null

      local raw_on_fail raw_goto_target
      raw_on_fail=$(_fc_get_field "on_fail" "$raw_block")
      case "$raw_on_fail" in
        goto:*)
          raw_goto_target="${raw_on_fail#goto:}"
          if ! printf ' %s ' "$valid_ids" | grep -q " ${raw_goto_target} "; then
            echo "[ERROR] flow_validate_steps: on_fail goto 대상 '${raw_goto_target}' 이 존재하지 않는 step id" >&2
            errors=$((errors + 1))
          fi
          ;;
      esac
    done <<EOF
$raw_lines
EOF
  fi

  # 각 step 검증
  while IFS=$'\037' read -r id soul task deps; do
    # id 필수
    if [ -z "$id" ]; then
      echo "[ERROR] flow_validate_steps: id 필드 누락 (step: ${task:-?})" >&2
      errors=$((errors + 1))
      continue
    fi

    # task 필수
    if [ -z "$task" ]; then
      echo "[ERROR] flow_validate_steps: step '${id}' task 필드 누락" >&2
      errors=$((errors + 1))
    fi

    # soul은 빈 문자열 허용 (host 직접 처리) — 검증 생략

    # deps가 존재하는 id를 참조하는지 검사
    for dep in $deps; do
      [ -z "$dep" ] && continue
      if ! printf ' %s ' "$valid_ids" | grep -q " ${dep} "; then
        echo "[ERROR] flow_validate_steps: step '${id}' deps에 존재하지 않는 id '${dep}' 참조" >&2
        errors=$((errors + 1))
      fi
    done
  done <<EOF
$parsed
EOF

  return "$errors"
}
