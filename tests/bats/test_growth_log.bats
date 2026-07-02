#!/usr/bin/env bats
# test_growth_log.bats — Zen 작성 영역 (placeholder)
# Bolt가 인프라 셋업 완료. Zen이 아래에 실제 테스트를 채운다.
#
# helper API: setup/teardown (격리 GOLEM_PROJECT), load_fixture, assert_jsonl_field
# fixture: fixtures/growth-log/sample.jsonl

load "test_helper"

@test "growth-log: 빈 파일에 첫 entry append → JSONL 1라인" {
  export GOLEM_DIR="$GOLEM_PROJECT/.golem"
  export GROWTH_DIR="$GOLEM_PROJECT/.golem/growth-log"
  mkdir -p "$GROWTH_DIR"
  source "$GOLEM_ROOT/lib/growth-log.sh"
  # lib 로드 후 GROWTH_DIR 다시 설정 (override 방지)
  export GROWTH_DIR="$GOLEM_PROJECT/.golem/growth-log"

  growth_log_append "testuser" "첫 태스크" "success" 2 3

  local log_file="$GROWTH_DIR/testuser.jsonl"
  [ -f "$log_file" ]
  [ "$(wc -l < "$log_file")" -eq 1 ]
}

@test "growth-log: 필수 필드 5종 존재 (date, task, result, files_changed, tests_passed)" {
  export GOLEM_DIR="$GOLEM_PROJECT/.golem"
  export GROWTH_DIR="$GOLEM_PROJECT/.golem/growth-log"
  mkdir -p "$GROWTH_DIR"
  source "$GOLEM_ROOT/lib/growth-log.sh"
  export GROWTH_DIR="$GOLEM_PROJECT/.golem/growth-log"

  growth_log_append "testuser2" "태스크" "success" 5 10

  local entry=$(cat "$GROWTH_DIR/testuser2.jsonl")
  echo "$entry" | grep -q '"date"'
  echo "$entry" | grep -q '"task"'
  echo "$entry" | grep -q '"result"'
  echo "$entry" | grep -q '"files_changed"'
  echo "$entry" | grep -q '"tests_passed"'
}

@test "growth-log: tokens_in=0 → cost 필드 append 안 함" {
  export GOLEM_DIR="$GOLEM_PROJECT/.golem"
  export GROWTH_DIR="$GOLEM_PROJECT/.golem/growth-log"
  mkdir -p "$GROWTH_DIR"
  source "$GOLEM_ROOT/lib/growth-log.sh"
  export GROWTH_DIR="$GOLEM_PROJECT/.golem/growth-log"

  growth_log_append "testuser3" "비용없음" "success" 1 2 "" "" 0 0 0 0 "" 0

  local entry=$(cat "$GROWTH_DIR/testuser3.jsonl")
  ! echo "$entry" | grep -q '"tokens_in"'
  ! echo "$entry" | grep -q '"tokens_out"'
  ! echo "$entry" | grep -q '"cost_usd"'
}

@test "growth-log: tokens_in>0 → cost 필드 모두 append" {
  export GOLEM_DIR="$GOLEM_PROJECT/.golem"
  export GROWTH_DIR="$GOLEM_PROJECT/.golem/growth-log"
  mkdir -p "$GROWTH_DIR"
  source "$GOLEM_ROOT/lib/growth-log.sh"
  export GROWTH_DIR="$GOLEM_PROJECT/.golem/growth-log"

  growth_log_append "testuser4" "비용있음" "success" 2 5 "" "" 100 50 10 0.015 "sonnet" 2500

  local entry=$(cat "$GROWTH_DIR/testuser4.jsonl")
  echo "$entry" | grep -q '"tokens_in":100'
  echo "$entry" | grep -q '"tokens_out":50'
  echo "$entry" | grep -q '"tokens_cache":10'
  echo "$entry" | grep -q '"cost_usd"'
  echo "$entry" | grep -q '"model":"sonnet"'
  echo "$entry" | grep -q '"duration_ms":2500'
}

@test "growth-log: result=fail 정상 append" {
  export GOLEM_DIR="$GOLEM_PROJECT/.golem"
  export GROWTH_DIR="$GOLEM_PROJECT/.golem/growth-log"
  mkdir -p "$GROWTH_DIR"
  source "$GOLEM_ROOT/lib/growth-log.sh"
  export GROWTH_DIR="$GOLEM_PROJECT/.golem/growth-log"

  growth_log_append "testuser5" "실패" "fail" 0 0

  local log_file="$GROWTH_DIR/testuser5.jsonl"
  [ -f "$log_file" ]
  cat "$log_file" | grep -q '"result":"fail"'
}

# ─────────────────────────────────────────────────────────
# 교차 구현 골든 계약 — bash 작성자 ↔ tests/golden/growth-log.golden.jsonl
# (python 측은 web/gateway/tests/test_growth_log_contract.py 가 같은 파일 검증)
# ─────────────────────────────────────────────────────────

@test "growth-log: 골든 계약 — bash 작성자 출력이 골든과 byte-동일" {
  golem_load_lib growth-log

  growth_log_append goldy '골든 "인용" 태스크 | 파이프' success 2 3 >/dev/null
  growth_log_append goldy '비용 추적 태스크' success 0 0 "" "" 100 50 20 0.123 sonnet 1500 >/dev/null

  local written="$GROWTH_DIR/goldy.jsonl"
  [ -f "$written" ]
  # date 필드만 정규화 후 골든과 diff
  sed 's/"date":"[0-9-]*"/"date":"DATE"/' "$written" > "$TEST_PROJECT/normalized.jsonl"
  diff "$TEST_PROJECT/normalized.jsonl" "${GOLEM_ROOT}/tests/golden/growth-log.golden.jsonl"
}

@test "growth-log: 컴팩트 구분자 계약 — '\": ' 형태 금지" {
  golem_load_lib growth-log
  growth_log_append goldy 'compact-check' success >/dev/null
  ! grep -q '": ' "$GROWTH_DIR/goldy.jsonl"
}
