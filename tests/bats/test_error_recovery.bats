#!/usr/bin/env bats
# test_error_recovery.bats — lib/error-recovery.sh (축소판: 프롬프트 생성기 계약)
#
# 계약: error_retry/error_delegate 는 stdout 에 프롬프트만 출력한다
# (호출자가 그대로 agent_run 에 파이프). 상태 메시지는 stderr.
# OMC 잔재("OMC 에이전트", soul_to_omc_agent)는 0건이어야 한다.

load "test_helper"

_setup_souls() {
  load_fixture "souls/ryn.md" "$TEST_PROJECT/.golem/souls/ryn.md"
  load_fixture "souls/zen.md" "$TEST_PROJECT/.golem/souls/zen.md"
  load_fixture "souls/nex.md" "$TEST_PROJECT/.golem/souls/nex.md"
}

@test "recovery: error_retry — 실패 원인·시도 횟수가 프롬프트에 포함" {
  _setup_souls
  golem_load_lib error-recovery

  run error_retry ryn "REST API 구현" "타입 오류" 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"타입 오류"* ]]
  [[ "$output" == *"시도 1"* ]] || [[ "$output" == *"(시도 1/"* ]]
  [[ "$output" == *"REST API 구현"* ]]
}

@test "recovery: error_retry — OMC 잔재 문자열 0건" {
  _setup_souls
  golem_load_lib error-recovery

  run error_retry ryn "태스크" "이유" 1
  [ "$status" -eq 0 ]
  [[ "$output" != *"OMC"* ]]
}

@test "recovery: error_retry — 재시도 상한 초과 시 return 1" {
  _setup_souls
  golem_load_lib error-recovery

  run error_retry ryn "태스크" "이유" $((GOLEM_MAX_RETRY + 1))
  [ "$status" -eq 1 ]
}

@test "recovery: error_retry — 미존재 SOUL 은 return 1" {
  _setup_souls
  golem_load_lib error-recovery

  run error_retry ghost "태스크" "이유" 1
  [ "$status" -eq 1 ]
}

@test "recovery: error_delegate — 대체 SOUL 위임 프롬프트 (OMC 0건, director 제외)" {
  _setup_souls
  golem_load_lib error-recovery

  # zen specialty(bash-testing)에 매칭되는 키워드 사용 — ryn(원본)·nex(director) 제외 검증
  run error_delegate ryn "bash-testing 스위트 보강" "3회 실패"
  [ "$status" -eq 0 ]
  [[ "$output" == *"위임"* ]]
  [[ "$output" != *"OMC"* ]]
  [[ "$output" == *"Zen"* ]]
  [[ "$output" != *"Delegate — Nex"* ]]
}

@test "recovery: error_recover 오케스트레이터는 제거됨 (no-op 위장 차단)" {
  golem_load_lib error-recovery
  ! command -v error_recover
}

@test "recovery: forge recover verb 제거 — usage 에러" {
  run bash "${GOLEM_ROOT}/forge.sh" recover ryn "t" "r"
  [ "$status" -ne 0 ]
}

@test "recovery: error_classify — timeout 은 재시도 가능 분류" {
  golem_load_lib error-recovery
  run error_classify timeout "wall clock exceeded"
  [ "$status" -eq 0 ]
  [[ "$output" == "timeout|backoff_retry|yes|"* ]]
}

@test "contract: soul_to_omc_agent shim 은 lib 전체에서 삭제됨" {
  # 함수 정의·호출 모두 0건 (주석 제외)
  run bash -c "grep -rn 'soul_to_omc_agent' '${GOLEM_ROOT}/lib' '${GOLEM_ROOT}/forge.sh' | grep -v '^[^:]*:[0-9]*:#' | grep -v ':[[:space:]]*#'"
  [ -z "$output" ]
}
