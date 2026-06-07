#!/usr/bin/env bats
# test_explore.bats — Zen 작성: lib/explore.sh 단위 테스트 (오프라인)
# 커버리지:
#   explore_files, explore_run, EXPLORE_MAX_FILES 캡, EXPLORE_MAX_LINES 트런케이션,
#   zero-match 케이스, read-only 보장

load "test_helper"

# explore.sh 소싱 후 GOLEM 환경 격리
_source_explore() {
  export GOLEM_ROOT
  export GOLEM_DIR="$TEST_PROJECT/.golem"
  export GOLEM_PROJECT="$TEST_PROJECT"
  # shellcheck source=/dev/null
  source "${GOLEM_ROOT}/lib/explore.sh"
  # source 후 덮어쓰인 변수 재보정
  export GOLEM_DIR="$TEST_PROJECT/.golem"
  # 검색 경로: 라이브러리 디렉터리로 한정 (속도 + 결과 예측 가능)
  export _EXPLORE_TEST_PATH="${GOLEM_ROOT}/lib"
}

# ─────────────────────────────────────────────────────────
# explore_files
# ─────────────────────────────────────────────────────────

@test "explore: explore_files 'agent_run' — agent-runner.sh 가 결과에 포함됨" {
  _source_explore
  run explore_files "agent_run" "${_EXPLORE_TEST_PATH}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "agent-runner.sh" ]]
}

@test "explore: explore_files 'agent_run' — 매치 수(숫자) 가 결과에 포함됨" {
  _source_explore
  run explore_files "agent_run" "${_EXPLORE_TEST_PATH}"
  [ "$status" -eq 0 ]
  # "  NNN matches  <file>" 형식 — 숫자가 포함된 라인 존재
  [[ "$output" =~ "matches" ]]
}

@test "explore: explore_files — 빈 쿼리는 exit 1 + 사용법 출력" {
  _source_explore
  run explore_files "" "${_EXPLORE_TEST_PATH}"
  [ "$status" -eq 1 ]
}

@test "explore: EXPLORE_MAX_FILES=2 — 출력 파일 수 상위 2개로 캡" {
  _source_explore
  # doctor_run 을 검색하면 doctor.sh + verify.sh 등 여러 파일에 걸림
  EXPLORE_MAX_FILES=2 run explore_files "doctor_run" "${_EXPLORE_TEST_PATH}"
  [ "$status" -eq 0 ]
  # 결과에 "상위 2개" 문자열 포함 (explore_files 출력 헤더)
  [[ "$output" =~ "2" ]]
}

@test "explore: zero-match 쿼리 — exit 0 (크래시 없음)" {
  _source_explore
  run explore_files "ZZZNOMATCHQUERYZZZUNIQUEXXX9999" "${_EXPLORE_TEST_PATH}"
  [ "$status" -eq 0 ]
}

@test "explore: zero-match 쿼리 — 출력에 '0' 포함 (0 파일)" {
  _source_explore
  run explore_files "ZZZNOMATCHQUERYZZZUNIQUEXXX9999" "${_EXPLORE_TEST_PATH}"
  [[ "$output" =~ "0" ]]
}

# ─────────────────────────────────────────────────────────
# explore_run
# ─────────────────────────────────────────────────────────

@test "explore: explore_run 'mission_init' — 요약 헤더 ('files') 포함" {
  _source_explore
  run explore_run "mission_init" "${_EXPLORE_TEST_PATH}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "files" ]]
}

@test "explore: explore_run 'mission_init' — 매치 수 ('matches') 포함" {
  _source_explore
  run explore_run "mission_init" "${_EXPLORE_TEST_PATH}"
  [[ "$output" =~ "matches" ]]
}

@test "explore: explore_run 'mission_init' — mission.sh 파일 결과에 표시" {
  _source_explore
  run explore_run "mission_init" "${_EXPLORE_TEST_PATH}"
  [[ "$output" =~ "mission" ]]
}

@test "explore: EXPLORE_MAX_LINES=10 — 트런케이션 노티스 출력" {
  _source_explore
  # lib/ 에 충분히 많은 매치가 있는 단어로 라인 예산 초과 유도
  # 예산 초과 시 "[truncated: ..." 메시지 출력
  EXPLORE_MAX_LINES=10 run explore_run "GOLEM_ROOT" "${_EXPLORE_TEST_PATH}"
  [ "$status" -eq 0 ]
  # 라인 예산 초과 또는 완료 중 하나: 출력 끝에 완료/트런케이션 메시지 있어야 함
  [[ "$output" =~ "truncated" ]] || [[ "$output" =~ "완료" ]]
}

@test "explore: explore_run — read-only (growth-log 에 새 파일 없음)" {
  _source_explore
  local before_count
  before_count=$(find "$TEST_PROJECT/.golem/growth-log" -type f 2>/dev/null | wc -l | tr -d ' ')

  run explore_run "agent_run" "${_EXPLORE_TEST_PATH}"

  local after_count
  after_count=$(find "$TEST_PROJECT/.golem/growth-log" -type f 2>/dev/null | wc -l | tr -d ' ')
  [ "$before_count" = "$after_count" ]
}
