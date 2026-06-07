#!/usr/bin/env bats
# test_doctor.bats — Zen 작성: lib/doctor.sh 단위 테스트 (오프라인)
# 커버리지:
#   doctor_run, doctor_run --verbose
#   read-only 보장, 섹션 헤더, 요약 라인, claude PATH 체크

load "test_helper"

# doctor.sh 소싱 후 GOLEM 환경 격리 재설정
_source_doctor() {
  export GOLEM_ROOT
  export GOLEM_DIR="$TEST_PROJECT/.golem"
  export GOLEM_PROJECT="$TEST_PROJECT"
  # shellcheck source=/dev/null
  source "${GOLEM_ROOT}/lib/doctor.sh"
  # source 후 덮어쓰인 변수 재보정
  export GOLEM_DIR="$TEST_PROJECT/.golem"
}

# ─────────────────────────────────────────────────────────
# 기본 실행 및 종료 코드
# ─────────────────────────────────────────────────────────

@test "doctor: doctor_run — claude 설치 환경에서 exit 0" {
  _source_doctor
  run doctor_run
  # claude 가 PATH 에 있으면 CRITICAL 체크 통과 → exit 0
  [ "$status" -eq 0 ]
}

@test "doctor: doctor_run — 출력에 [CORE] 섹션 헤더 포함" {
  _source_doctor
  run doctor_run
  [[ "$output" =~ "[CORE]" ]]
}

@test "doctor: doctor_run — 출력에 [DEPENDENCIES] 섹션 헤더 포함" {
  _source_doctor
  run doctor_run
  [[ "$output" =~ "[DEPENDENCIES]" ]]
}

@test "doctor: doctor_run — 출력에 [PROJECT] 섹션 헤더 포함" {
  _source_doctor
  run doctor_run
  [[ "$output" =~ "[PROJECT]" ]]
}

@test "doctor: doctor_run — 출력에 '진단 결과:' 요약 라인 포함" {
  _source_doctor
  run doctor_run
  [[ "$output" =~ "진단 결과:" ]]
}

@test "doctor: doctor_run — claude CLI ✓ 체크 포함 (claude가 PATH에 있음)" {
  _source_doctor
  run doctor_run
  # claude 가 PATH 에 있으므로 체크마크 또는 "claude CLI" 통과 표시
  [[ "$output" =~ "claude CLI" ]]
}

@test "doctor: doctor_run --verbose — 에러 없이 실행 (exit 0)" {
  _source_doctor
  run doctor_run --verbose
  [ "$status" -eq 0 ]
}

@test "doctor: doctor_run — read-only 보장 (sentinel 파일 미변경)" {
  _source_doctor
  # sentinel 파일 생성
  local sentinel="$TEST_PROJECT/.golem/growth-log/sentinel_doctor_test.txt"
  echo "untouched" > "$sentinel"
  local before
  before=$(cat "$sentinel")

  # doctor_run 은 상태 기록을 하면 안 됨
  run doctor_run
  [ "$status" -eq 0 ]

  # sentinel 내용이 그대로여야 함
  local after
  after=$(cat "$sentinel")
  [ "$before" = "$after" ]
}

@test "doctor: doctor_run — growth-log 디렉토리에 새 파일 생성 없음" {
  _source_doctor
  local before_count
  before_count=$(find "$TEST_PROJECT/.golem/growth-log" -type f 2>/dev/null | wc -l | tr -d ' ')

  run doctor_run

  local after_count
  after_count=$(find "$TEST_PROJECT/.golem/growth-log" -type f 2>/dev/null | wc -l | tr -d ' ')
  [ "$before_count" = "$after_count" ]
}
