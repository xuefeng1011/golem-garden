#!/usr/bin/env bats
# test_insights.bats — insights 실패 유형 분해 (P0-5 회귀)
# 픽스처 growth log 로 result 값별 집계 정확성과 유령 라인 배제를 검증한다.

load "test_helper"

setup() {
  TEST_PROJECT="$(mktemp -d "${TMPDIR:-/tmp}/insights-test.XXXXXX")"
  export GOLEM_ROOT
  GOLEM_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export GOLEM_DIR="$TEST_PROJECT/.golem" GOLEM_PROJECT="$TEST_PROJECT"
  mkdir -p "$GOLEM_DIR/growth-log" "$GOLEM_DIR/souls"

  # 픽스처 SOUL (글로벌 로그와 이름 충돌 없는 고유명)
  cat > "$GOLEM_DIR/souls/zzfixture.md" <<'EOF'
---
name: zzfixture
role: qa-tester
rank: novice
model: haiku
specialty: testing
---

# zzfixture
EOF

  # 픽스처 growth log: success 2 + fail 1 + timeout 1 + turn_cap 2 + checkpoint 1 + exhausted 1
  #                    + 미지 값 1 (partial) + result 없는 잡라인 1
  cat > "$GOLEM_DIR/growth-log/zzfixture.jsonl" <<'EOF'
{"date":"2026-07-12","soul":"zzfixture","task":"t1","result":"success","model":"haiku","cost_usd":0.01}
{"date":"2026-07-12","soul":"zzfixture","task":"t2","result":"success","model":"haiku","cost_usd":0.01}
{"date":"2026-07-12","soul":"zzfixture","task":"t3","result":"fail","model":"haiku","cost_usd":0.01}
{"date":"2026-07-12","soul":"zzfixture","task":"t4","result":"timeout","model":"haiku","cost_usd":0.01}
{"date":"2026-07-12","soul":"zzfixture","task":"t5","result":"turn_cap","model":"haiku","cost_usd":0.01}
{"date":"2026-07-12","soul":"zzfixture","task":"t6","result":"turn_cap","model":"haiku","cost_usd":0.01}
{"date":"2026-07-12","soul":"zzfixture","task":"t7","result":"checkpoint","model":"haiku","cost_usd":0.01,"slice":1}
{"date":"2026-07-12","soul":"zzfixture","task":"t8","result":"exhausted","model":"haiku","cost_usd":0.01,"slice":4}
{"date":"2026-07-12","soul":"zzfixture","task":"t9","result":"partial","model":"haiku","cost_usd":0.01}
{"date":"2026-07-12","soul":"zzfixture","note":"summary junk line without a res-ult field"}
EOF

  source "${GOLEM_ROOT}/lib/insights.sh"
  export GOLEM_DIR="$TEST_PROJECT/.golem"
}

teardown() {
  rm -rf "$TEST_PROJECT"
}

@test "insights: 실패 유형 분해 — result 값별 정확 집계 + 미지 값은 기타" {
  run insights_soul zzfixture
  [ "$status" -eq 0 ]
  # 총계: result:"..." 라인 9건만 (잡라인 배제)
  [[ "$output" == *"태스크: 9건 (성공 2"* ]]
  [[ "$output" == *"실패(fail): 1건"* ]]
  [[ "$output" == *"타임아웃: 1건"* ]]
  [[ "$output" == *"턴캡: 2건"* ]]
  [[ "$output" == *"소진(exhausted): 1건"* ]]
  [[ "$output" == *"기타: 1건"* ]]
  # 체크포인트는 별도 표기
  [[ "$output" == *"체크포인트: 1건 (승계 대기)"* ]]
}

@test "insights: 팀 뷰 — Failures 컬럼 존재 + 유형 축약 표기" {
  run insights_team
  [ "$status" -eq 0 ]
  [[ "$output" == *"Failures"* ]]
  # 픽스처 SOUL 행: 1f·1t·2c·1e 축약 표기 (fail·timeout·turn_cap·exhausted)
  [[ "$output" == *"1f·1t·2c·1e"* ]]
}
