#!/usr/bin/env bats
# test_json_lite.bats — lib/json-lite.sh 공용 escape-aware 워커
# B-5: _json_get_string_array 신설 커버리지 (쉼표/이스케이프 따옴표/부재 키)

load "test_helper"

_source_json_lite() {
  export GOLEM_ROOT
  # shellcheck source=/dev/null
  source "${GOLEM_ROOT}/lib/json-lite.sh"
}

@test "json-lite: _json_get_string_array — 기본 배열 항목 2개" {
  _source_json_lite
  run _json_get_string_array '{"id":"s1","rubric":["항목1","항목2"]}' rubric
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 2 ]
  [[ "$output" == *"항목1"* ]]
  [[ "$output" == *"항목2"* ]]
}

@test "json-lite: _json_get_string_array — 항목 내부 일반 쉼표 보존(오분할 없음)" {
  _source_json_lite
  run _json_get_string_array '{"rubric":["a.sh 존재, 확인 필요","b.sh 테스트"]}' rubric
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 2 ]
  [[ "$output" == *"a.sh 존재, 확인 필요"* ]]
}

@test "json-lite: _json_get_string_array — 이스케이프 따옴표 unescape" {
  _source_json_lite
  run _json_get_string_array '{"rubric":["그는 \"완료\"라 했다"]}' rubric
  [ "$status" -eq 0 ]
  [[ "$output" == *'그는 "완료"라 했다'* ]]
}

@test "json-lite: _json_get_string_array — 키 부재 시 빈 출력 + return 0" {
  _source_json_lite
  run _json_get_string_array '{"id":"s1"}' rubric
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
