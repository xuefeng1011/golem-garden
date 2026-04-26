#!/usr/bin/env bats
# test_rank_system.bats — Zen 작성 영역 (placeholder)
# Bolt가 인프라 셋업 완료. Zen이 아래에 실제 테스트를 채운다.
#
# 테스트 대상: lib/rank-system.sh
# fixture: fixtures/souls/*.md, fixtures/growth-log/sample.jsonl

load "test_helper"

@test "rank-system: novice → junior 임계값 (task_count ≥ 10)" {
  source "$GOLEM_ROOT/lib/rank-system.sh"

  local result
  result=$(rank_should_promote "novice" 9 0) || true
  [ -z "$result" ]

  result=$(rank_should_promote "novice" 10 0)
  [ "$result" = "junior" ]

  result=$(rank_should_promote "novice" 15 0)
  [ "$result" = "junior" ]
}

@test "rank-system: junior → senior 조건 (task ≥50 AND streak ≥10)" {
  source "$GOLEM_ROOT/lib/rank-system.sh"

  local result
  result=$(rank_should_promote "junior" 50 9) || true
  [ -z "$result" ]

  result=$(rank_should_promote "junior" 49 10) || true
  [ -z "$result" ]

  result=$(rank_should_promote "junior" 50 10)
  [ "$result" = "senior" ]
}

@test "rank-system: senior → lead 임계값 (task_count ≥ 100)" {
  source "$GOLEM_ROOT/lib/rank-system.sh"

  local result
  result=$(rank_should_promote "senior" 99 0) || true
  [ -z "$result" ]

  result=$(rank_should_promote "senior" 100 0)
  [ "$result" = "lead" ]
}

@test "rank-system: 조건 미충족 → promote 불가 (idempotent)" {
  source "$GOLEM_ROOT/lib/rank-system.sh"

  # task_count < 10이면 junior로 승급 불가
  local result
  result=$(rank_should_promote "novice" 5 0) || true
  [ -z "$result" ]
}

@test "rank-system: lead → master 임계값 (task_count ≥ 200)" {
  source "$GOLEM_ROOT/lib/rank-system.sh"

  local result
  result=$(rank_should_promote "lead" 199 0) || true
  [ -z "$result" ]

  result=$(rank_should_promote "lead" 200 0)
  [ "$result" = "master" ]
}

@test "rank-system: streak 감소 → 승급 차단 (junior streak < 10)" {
  source "$GOLEM_ROOT/lib/rank-system.sh"

  # task_count=50이어도 streak=5 (fail로 리셋) → 승급 불가
  local result
  result=$(rank_should_promote "junior" 50 5) || true
  [ -z "$result" ]

  # streak=10 (무결함) → 승급 가능
  result=$(rank_should_promote "junior" 50 10)
  [ "$result" = "senior" ]
}
