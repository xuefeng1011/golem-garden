#!/usr/bin/env bats
# test_p0_contracts.bats — P0 계약·안전장치 테스트 (PERF-HARNESS-PLAN §3 P0)
#
# 커버리지:
#   P0-1: _verify_parse_verdict 마커 계약 (마커 > 레거시 첫 줄 > UNCLEAR)
#         verify_run 재질의 1회 + 안전 기본값 FAIL (구 SKIP 게이트 구멍 차단)
#   P0-2: soul_match_score 리터럴 매칭 경화 (정규식 메타문자 오탐 차단)
#   P0-3: _agent_budget_preflight 예산 사전 차단 + 오버라이드
#   P0-4: guard-novice.sh 차단 전환 (exit 2) + 보수적 랭크 기본값
#
# 재귀 방지: GOLEM_PROJECT=TEST_PROJECT 에는 tests/bats/run.sh 가 없어
# _verify_run_tests 가 SKIP(2) 경로로 빠진다 (test_verify.bats 와 동일 전략).

load "test_helper"

_source_verify() {
  export GOLEM_ROOT
  export GOLEM_DIR="$TEST_PROJECT/.golem"
  export GOLEM_PROJECT="$TEST_PROJECT"
  # shellcheck source=/dev/null
  source "${GOLEM_ROOT}/lib/verify.sh"
  export GOLEM_DIR="$TEST_PROJECT/.golem"
}

# ─────────────────────────────────────────────────────────
# P0-1: _verify_parse_verdict 마커 계약
# ─────────────────────────────────────────────────────────

@test "p0-1: 마커 [VERDICT: PASS] → PASS" {
  _source_verify
  run _verify_parse_verdict $'[VERDICT: PASS]\n이유: 테스트 전부 통과'
  [ "$status" -eq 0 ]
  [ "$output" = "PASS" ]
}

@test "p0-1: 마커 [VERDICT: FAIL] 이 둘째 줄에 있어도 인식 → FAIL" {
  _source_verify
  run _verify_parse_verdict $'검토 결과입니다.\n[VERDICT: FAIL]\n이유: 경계값 누락'
  [ "$output" = "FAIL" ]
}

@test "p0-1: 마커 대소문자 무시 [verdict: pass] → PASS" {
  _source_verify
  run _verify_parse_verdict '[verdict: pass]'
  [ "$output" = "PASS" ]
}

@test "p0-1: 레거시 첫 줄 PASS → PASS (하위 호환)" {
  _source_verify
  run _verify_parse_verdict $'PASS\n이유: 양호'
  [ "$output" = "PASS" ]
}

@test "p0-1: 본문에만 PASS 인용 — 첫 줄/마커 아님 → UNCLEAR (구 전체 스캔 오탐 차단)" {
  _source_verify
  run _verify_parse_verdict $'판정 근거를 설명합니다.\n결정론 테스트는 PASS 였으나 코드 품질이 의심됩니다.'
  [ "$output" = "UNCLEAR" ]
}

@test "p0-1: 빈 출력 → UNCLEAR" {
  _source_verify
  run _verify_parse_verdict ""
  [ "$output" = "UNCLEAR" ]
}

# ─────────────────────────────────────────────────────────
# P0-1: verify_run — 재질의 + 안전 기본값 FAIL (agent_run 모킹)
# ─────────────────────────────────────────────────────────

@test "p0-1: 심판 출력 불명확 (재질의 포함) → 안전 기본값 FAIL, exit 1" {
  _source_verify
  # 모킹: 항상 마커 없는 애매한 답변 → 1차 + 재질의 모두 UNCLEAR
  agent_run() { echo "음, 전반적으로 나쁘지 않은 것 같습니다."; }
  run verify_run "p0 대상" "zen"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "안전 기본값 FAIL" ]]
}

@test "p0-1: 심판 마커 PASS → overall PASS, exit 0" {
  _source_verify
  agent_run() { printf '[VERDICT: PASS]\n이유: 충분히 검증됨\n'; }
  run verify_run "p0 대상" "zen"
  [ "$status" -eq 0 ]
}

@test "p0-1: 1차 불명확 + 재질의에서 마커 FAIL → FAIL 판정 반영" {
  _source_verify
  # 1차 호출은 애매, 2차(재질의) 호출은 마커 — 호출 횟수 파일로 추적
  agent_run() {
    local cnt_file="$TEST_PROJECT/.agent_run_count"
    local cnt=0
    [ -f "$cnt_file" ] && cnt=$(cat "$cnt_file")
    cnt=$((cnt + 1))
    echo "$cnt" > "$cnt_file"
    if [ "$cnt" -eq 1 ]; then echo "애매한 첫 답변"; else echo "[VERDICT: FAIL]"; fi
  }
  run verify_run "p0 대상" "zen"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "FAIL" ]]
}

# ─────────────────────────────────────────────────────────
# P0-2: soul_match_score 리터럴 매칭
# ─────────────────────────────────────────────────────────

_make_soul() {
  cat > "$TEST_PROJECT/.golem/souls/tester.md" <<'SOUL'
---
name: Tester
role: backend-developer
rank: novice
specialty: [golang, grpc, timeseries]
model: sonnet
created: 2026-06-10
---
SOUL
}

@test "p0-2: specialty 일치 키워드당 +10 (golang grpc → 20)" {
  golem_load_lib soul-parser
  _make_soul
  run soul_match_score "$TEST_PROJECT/.golem/souls/tester.md" "golang grpc"
  [ "$output" = "20" ]
}

@test "p0-2: 불일치 키워드 → 0" {
  golem_load_lib soul-parser
  _make_soul
  run soul_match_score "$TEST_PROJECT/.golem/souls/tester.md" "css vue"
  [ "$output" = "0" ]
}

@test "p0-2: 정규식 메타문자 '.' 가 와일드카드로 동작하지 않음 (go.ang → 0)" {
  golem_load_lib soul-parser
  _make_soul
  # grep -F 이전엔 'go.ang' 의 '.' 이 'l' 에 매칭돼 +10 오탐
  run soul_match_score "$TEST_PROJECT/.golem/souls/tester.md" "go.ang"
  [ "$output" = "0" ]
}

# ─────────────────────────────────────────────────────────
# P0-3: _agent_budget_preflight
# ─────────────────────────────────────────────────────────

_write_budget() {
  local status="$1"
  cat > "$TEST_PROJECT/.golem/budget-state.json" <<EOF
{"token_budget":500000,"dollar_budget":10.00,"tokens_used":600000,"dollars_spent":12.000,"turns":9,"stagnant_turns":0,"status":"${status}","started":"2026-06-10T00:00:00"}
EOF
}

@test "p0-3: status=exceeded → 소환 차단 (return 1 + BLOCKED 메시지)" {
  golem_load_lib agent-runner
  _write_budget "exceeded"
  run _agent_budget_preflight
  [ "$status" -eq 1 ]
  [[ "$output" =~ "BLOCKED" ]]
}

@test "p0-3: status=ok → 통과" {
  golem_load_lib agent-runner
  _write_budget "ok"
  run _agent_budget_preflight
  [ "$status" -eq 0 ]
}

@test "p0-3: 예산 파일 없음 → 통과 (추적 미시작 허용)" {
  golem_load_lib agent-runner
  run _agent_budget_preflight
  [ "$status" -eq 0 ]
}

@test "p0-3: GOLEM_BUDGET_OVERRIDE=1 → exceeded 여도 통과" {
  golem_load_lib agent-runner
  _write_budget "exceeded"
  export GOLEM_BUDGET_OVERRIDE=1
  run _agent_budget_preflight
  [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────────────────
# P0-4: guard-novice.sh 차단 전환
# ─────────────────────────────────────────────────────────

_setup_git_two_modified() {
  cd "$TEST_PROJECT" || return 1
  git init -q
  echo a > f1.txt
  echo b > f2.txt
  git add .
  git -c user.email=t@t.t -c user.name=t commit -qm init
  echo a2 > f1.txt
  echo b2 > f2.txt
}

_guard() { echo "${GOLEM_ROOT}/.claude/hooks/guard-novice.sh"; }

@test "p0-4: SOUL 컨텍스트 없음 (호스트 세션) → 통과 (exit 0)" {
  _setup_git_two_modified
  run bash -c 'echo "" | env -u GOLEM_SOUL_NAME -u GOLEM_SOUL_RANK bash "$1"' _ "$(_guard)"
  [ "$status" -eq 0 ]
}

@test "p0-4: novice + 2개 파일 수정 → 차단 (exit 2 + BLOCKED)" {
  _setup_git_two_modified
  run bash -c 'echo "" | GOLEM_SOUL_NAME=tester GOLEM_SOUL_RANK=novice bash "$1"' _ "$(_guard)"
  [ "$status" -eq 2 ]
  [[ "$output" =~ "BLOCKED" ]]
}

@test "p0-4: 이름만 있고 랭크 미상 → novice 간주, 차단 (보수적 기본값)" {
  _setup_git_two_modified
  run bash -c 'echo "" | env -u GOLEM_SOUL_RANK GOLEM_SOUL_NAME=tester bash "$1"' _ "$(_guard)"
  [ "$status" -eq 2 ]
}

@test "p0-4: junior + 2개 파일 수정 → 통과 (exit 0)" {
  _setup_git_two_modified
  run bash -c 'echo "" | GOLEM_SOUL_NAME=tester GOLEM_SOUL_RANK=junior bash "$1"' _ "$(_guard)"
  [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────────────────
# P2-4 발견: 비-UUID session_id 가드 (forge build e2e 라이브에서 발견)
# ─────────────────────────────────────────────────────────

@test "p2-4: 비-UUID session_id (forge sess_*) → 경고 + 새 UUID 폴백 (dry-run)" {
  golem_load_lib agent-runner
  run agent_run zen "테스트 태스크" "sess_1781103072_29773" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" =~ "UUID 형식이 아님" ]]
  # usage 라인의 session= 이 원래 비-UUID 값이면 안 됨
  ! printf '%s' "$output" | grep -q 'session=sess_1781103072_29773'
}

@test "p2-4: 유효한 UUID session_id → 경고 없이 그대로 사용 (dry-run)" {
  golem_load_lib agent-runner
  run agent_run zen "테스트 태스크" "123e4567-e89b-42d3-a456-426614174000" --dry-run
  [ "$status" -eq 0 ]
  ! [[ "$output" =~ "UUID 형식이 아님" ]]
  [[ "$output" =~ "session=123e4567-e89b-42d3-a456-426614174000" ]]
}

@test "p0-4: novice + 1개 파일 수정 → 통과 (단일 파일 원칙 준수)" {
  cd "$TEST_PROJECT" || return 1
  git init -q
  echo a > f1.txt
  git add .
  git -c user.email=t@t.t -c user.name=t commit -qm init
  echo a2 > f1.txt
  run bash -c 'echo "" | GOLEM_SOUL_NAME=tester GOLEM_SOUL_RANK=novice bash "$1"' _ "$(_guard)"
  [ "$status" -eq 0 ]
}
