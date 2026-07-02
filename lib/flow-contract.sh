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

# ── 공개 API ──────────────────────────────────────────────────────────────

# flow_extract_json — stdin 또는 파일에서 ```json 코드펜스 내용 추출
# 출력: JSON 텍스트 (stdout), 코드펜스 없으면 비-0 종료 + stderr
flow_extract_json() {
  local input
  if [ -n "$1" ] && [ -f "$1" ]; then
    input=$(cat "$1")
  else
    input=$(cat)
  fi

  # ```json ... ``` 블록 추출 (awk, 첫 번째 블록만)
  local json
  json=$(printf '%s\n' "$input" | awk '
    /^```json[[:space:]]*$/ { in_block=1; next }
    in_block && /^```[[:space:]]*$/ { exit }
    in_block { print }
  ')

  if [ -z "$json" ]; then
    echo "[ERROR] flow_extract_json: JSON 코드펜스를 찾을 수 없습니다" >&2
    return 1
  fi

  printf '%s\n' "$json"
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
