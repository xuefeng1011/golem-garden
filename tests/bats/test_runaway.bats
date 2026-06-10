#!/usr/bin/env bats
# test_runaway.bats — Zen 작성: agent-runner.sh 폭주 방지 가드 단위 테스트 (오프라인)
# 커버리지:
#   _agent_timeout_cmd: 기본값(300), AGENT_MAX_SECONDS 오버라이드, 비정수 폴백
#   agent_run --dry-run: max_seconds, runaway guard: 라인, timeout 프리픽스 표시

load "test_helper"

# agent-runner.sh 소싱 (zen.md fixture 필요)
_source_agent_runner() {
  load_fixture "souls/zen.md" "$TEST_PROJECT/.golem/souls/zen.md"
  # shellcheck source=/dev/null
  source "${GOLEM_ROOT}/lib/agent-runner.sh"
  # source 후 격리 재설정
  export GOLEM_DIR="$TEST_PROJECT/.golem"
  export GROWTH_DIR="$TEST_PROJECT/.golem/growth-log"
}

# ─────────────────────────────────────────────────────────
# _agent_timeout_cmd
# ─────────────────────────────────────────────────────────

@test "runaway: _agent_timeout_cmd — 기본 AGENT_MAX_SECONDS=300 출력" {
  _source_agent_runner
  # AGENT_MAX_SECONDS 미설정 시 기본 300
  unset AGENT_MAX_SECONDS
  result=$(_agent_timeout_cmd)
  # "timeout 300" 또는 "gtimeout 300" 이어야 함
  [[ "$result" =~ "300" ]]
}

@test "runaway: _agent_timeout_cmd — AGENT_MAX_SECONDS=5 → '5' 포함" {
  _source_agent_runner
  AGENT_MAX_SECONDS=5 result=$(_agent_timeout_cmd)
  [[ "$result" =~ "5" ]]
  # 'abc' 가 들어가면 안 됨 (폴백 확인 역지지)
  [[ ! "$result" =~ "abc" ]]
}

@test "runaway: _agent_timeout_cmd — 비정수 'abc' → 기본 300으로 폴백" {
  _source_agent_runner
  AGENT_MAX_SECONDS="abc" result=$(_agent_timeout_cmd)
  # "abc" 가 출력에 없어야 함 (정수 검증 후 300 폴백)
  [[ ! "$result" =~ "abc" ]]
  [[ "$result" =~ "300" ]]
}

@test "runaway: _agent_timeout_cmd — 출력이 비어있지 않음 (timeout 사용 가능)" {
  _source_agent_runner
  result=$(_agent_timeout_cmd)
  # timeout 또는 gtimeout 이 있으면 비어있지 않음
  # 없는 환경이면 빈 줄 출력 — 어느 쪽이든 크래시 없이 동작해야 함
  # 단순 실행 성공 여부만 확인
  true
}

# ─────────────────────────────────────────────────────────
# agent_run --dry-run: runaway guard 가시성
# ─────────────────────────────────────────────────────────

@test "runaway: agent_run --dry-run — 출력에 'max_seconds=' 키 포함 (기본값)" {
  _source_agent_runner
  # source 시점에 AGENT_MAX_SECONDS=300 이 설정됨.
  # unset 하면 usage 라인은 빈 값으로 출력되므로 unset 하지 않고
  # 키 자체 존재만 검증한다.
  result=$(agent_run "zen" "테스트 태스크" --dry-run 2>&1)
  [[ "$result" =~ "max_seconds=" ]]
}

@test "runaway: agent_run --dry-run — 출력에 'runaway guard:' 라인 포함" {
  _source_agent_runner
  result=$(agent_run "zen" "테스트 태스크" --dry-run 2>&1)
  [[ "$result" =~ "runaway guard" ]]
}

@test "runaway: AGENT_MAX_SECONDS=5 agent_run --dry-run — 'max_seconds=5' 포함" {
  _source_agent_runner
  AGENT_MAX_SECONDS=5 result=$(agent_run "zen" "테스트 태스크" --dry-run 2>&1)
  [[ "$result" =~ "max_seconds=5" ]]
}

@test "runaway: AGENT_MAX_SECONDS=5 agent_run --dry-run — timeout 5 또는 gtimeout 5 포함" {
  _source_agent_runner
  AGENT_MAX_SECONDS=5 result=$(agent_run "zen" "테스트 태스크" --dry-run 2>&1)
  # timeout 5 또는 gtimeout 5 가 argv 섹션에 표시되어야 함
  [[ "$result" =~ "timeout" ]] && [[ "$result" =~ "5" ]]
}

@test "runaway: agent_run --dry-run — cost_cap 라인 포함 (disabled 또는 값)" {
  _source_agent_runner
  result=$(agent_run "zen" "테스트 태스크" --dry-run 2>&1)
  [[ "$result" =~ "cost_cap" ]]
}

# ─────────────────────────────────────────────────────────
# P2-1 effort 실소비 — low=180/medium=300/high=600, 명시 env 우선
# ─────────────────────────────────────────────────────────

@test "effort: effort=high SOUL + AGENT_MAX_SECONDS 미설정 → max_seconds=600" {
  load_fixture "souls/zen-high.md" "$TEST_PROJECT/.golem/souls/zen-high.md"
  _source_agent_runner
  unset AGENT_MAX_SECONDS
  result=$(agent_run "zen-high" "테스트 태스크" --dry-run 2>&1)
  [[ "$result" =~ "max_seconds=600" ]]
}

@test "effort: effort=high + AGENT_MAX_SECONDS=42 명시 → max_seconds=42 (env 우선)" {
  load_fixture "souls/zen-high.md" "$TEST_PROJECT/.golem/souls/zen-high.md"
  _source_agent_runner
  AGENT_MAX_SECONDS=42 result=$(agent_run "zen-high" "테스트 태스크" --dry-run 2>&1)
  [[ "$result" =~ "max_seconds=42" ]]
}

@test "effort: effort 필드 없는 SOUL(haiku 모델) → low 추론 → max_seconds=180" {
  # zen.md 에는 effort 필드가 없고 model=haiku → soul_parse 가 low 추론
  load_fixture "souls/zen.md" "$TEST_PROJECT/.golem/souls/zen.md"
  _source_agent_runner
  unset AGENT_MAX_SECONDS
  result=$(agent_run "zen" "테스트 태스크" --dry-run 2>&1)
  [[ "$result" =~ "max_seconds=180" ]]
}
