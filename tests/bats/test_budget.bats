#!/usr/bin/env bats
# test_budget.bats — lib/budget.sh 비용 추정 (P3 캐시 단가 경화)

load "test_helper"


# ─────────────────────────────────────────────────────────
# P3 — 캐시 토큰 단가 + 풀 모델 ID 가격 매핑
# ─────────────────────────────────────────────────────────

@test "budget: 캐시 위주 런이 \$0.000 이 아님 (cache_read 0.1x 반영)" {
  golem_load_lib budget
  # total 0 + cache_read 100k → 100000 * 3 * 0.1 / 1e6 = 0.030
  run budget_estimate_cost sonnet 0 0 100000 0
  [ "$status" -eq 0 ]
  [[ "$output" == "0 0 0.030" ]]
}

@test "budget: cache_creation 은 1.25x 입력가" {
  golem_load_lib budget
  # 100000 * 3 * 1.25 / 1e6 = 0.375
  run budget_estimate_cost sonnet 0 0 0 100000
  [[ "$output" == "0 0 0.375" ]]
}

@test "budget: 풀 모델 ID claude-opus-4-8 — opus 단가 매핑" {
  golem_load_lib budget
  # in 800k*15 + out 200k*75 = 12 + 15 = 27.000
  run budget_estimate_cost claude-opus-4-8 1000000 0
  [[ "$output" == "800000 200000 27.000" ]]
}

@test "budget: 캐시 인자 생략 시 기존 동작 유지 (하위 호환)" {
  golem_load_lib budget
  run budget_estimate_cost sonnet 100000 0
  # 80k*3 + 20k*15 = 0.24 + 0.30 = 0.540
  [[ "$output" == "80000 20000 0.540" ]]
}
