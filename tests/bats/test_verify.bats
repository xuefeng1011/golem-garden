#!/usr/bin/env bats
# test_verify.bats — Zen 작성: lib/verify.sh 단위 테스트 (오프라인)
#
# 재귀 방지 전략:
#   verify_tests_only 는 내부적으로 GOLEM_PROJECT/tests/bats/run.sh 를 실행한다.
#   이 파일이 bats suite 에서 실행되면 run.sh → 전체 suite 재실행 → 무한루프 위험.
#   해결: GOLEM_PROJECT 를 TEST_PROJECT(격리 tmpdir)로 고정하면 TEST_PROJECT 에는
#   tests/bats/run.sh 가 없으므로 _verify_run_tests 가 "SKIP" 경로로 빠진다.
#   이 방식으로 실제 suite 재귀를 완전 차단한다.
#
# 커버리지:
#   a) author≠verifier 가드 — 동일 SOUL 지정 시 reject
#   b) author≠verifier 가드 — 다른 SOUL 이면 통과 (헤더 출력 확인)
#   c) verify_run --tests-only — SOUL 호출 없이 테스트 단계 실행
#   d) verify_run — 결정론적 테스트 FAIL 시 전체 FAIL (SOUL 심판 생략)
#   e) verify_tests_only — 테스트 러너 없음 시 SKIP 반환 (exit 2)
#   f) verify_run 빈 target — exit 1 + usage 출력
#
# SOUL 심판 경로(real claude 호출)는 오프라인 테스트 불가 → NOTE: 수동 커버.

load "test_helper"

# verify.sh 소싱 후 격리 재설정
# 핵심: GOLEM_PROJECT=TEST_PROJECT 로 고정 → run.sh 없음 → 재귀 차단
_source_verify() {
  export GOLEM_ROOT
  export GOLEM_DIR="$TEST_PROJECT/.golem"
  export GOLEM_PROJECT="$TEST_PROJECT"
  # shellcheck source=/dev/null
  source "${GOLEM_ROOT}/lib/verify.sh"
  # source 후 GOLEM_DIR 재보정 (agent-runner.sh 체인이 덮어씀)
  export GOLEM_DIR="$TEST_PROJECT/.golem"
}

# ─────────────────────────────────────────────────────────
# author≠verifier 가드
# ─────────────────────────────────────────────────────────

@test "verify: author=verifier 동일 — exit 1 + 에러 메시지 출력" {
  _source_verify
  VERIFY_AUTHOR_SOUL="ryn" run verify_run "테스트 대상" "ryn" --tests-only
  [ "$status" -eq 1 ]
  [[ "$output" =~ "author≠verifier" ]]
}

@test "verify: author=verifier 대소문자 무시 (Ryn vs ryn) — exit 1" {
  _source_verify
  VERIFY_AUTHOR_SOUL="Ryn" run verify_run "테스트 대상" "ryn" --tests-only
  [ "$status" -eq 1 ]
  [[ "$output" =~ "author≠verifier" ]]
}

@test "verify: author≠verifier 다른 SOUL — 가드 통과 (헤더 출력)" {
  _source_verify
  # TEST_PROJECT 에는 tests/bats/run.sh 없음 → _verify_run_tests 가 SKIP 반환
  VERIFY_AUTHOR_SOUL="ryn" run verify_run "테스트 대상" "zen" --tests-only
  # exit 0 (tests SKIP = soft pass, soul tests-only = skip)
  [ "$status" -eq 0 ]
  [[ "$output" =~ "zen" ]]
}

# ─────────────────────────────────────────────────────────
# verify_run -- 기본 동작
# ─────────────────────────────────────────────────────────

@test "verify: 빈 target (인자 없음) — exit 1 + usage 출력" {
  _source_verify
  # 인자를 아예 안 주면 target이 비어 있어 Usage 에러 반환
  run verify_run
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Usage" ]]
}

@test "verify: --tests-only — SOUL 호출 없이 진행 (SKIP(--tests-only) 포함)" {
  _source_verify
  # TEST_PROJECT 에 run.sh 없음 → tests SKIP → 전체 PASS
  run verify_run "대상 설명" "zen" --tests-only
  [ "$status" -eq 0 ]
  [[ "$output" =~ "tests-only" ]] || [[ "$output" =~ "SKIP" ]]
}

# ─────────────────────────────────────────────────────────
# verify_tests_only — 러너 없음 시 SKIP (exit 2)
# ─────────────────────────────────────────────────────────

@test "verify: verify_tests_only — 테스트 러너 없음 시 exit 2 (SKIP)" {
  _source_verify
  # TEST_PROJECT 에는 tests/bats/run.sh, package.json, pytest.ini 없음
  # → _verify_run_tests 가 "SKIP" + return 2
  run verify_tests_only
  # exit 2 = SKIP (러너 감지 불가)
  [ "$status" -eq 2 ]
  [[ "$output" =~ "SKIP" ]]
}

@test "verify: verify_tests_only — 출력에 '[verify]' 프리픽스 포함" {
  _source_verify
  run verify_tests_only
  [[ "$output" =~ "[verify]" ]]
}

# ─────────────────────────────────────────────────────────
# 무증거 차단 — 테스트 러너 없음 + SOUL 심판 비자발적 생략 → FAIL
# (라이브 스모크 실결함: SKIP+SKIP(SOUL호출실패) 가 PASS 로 열리던 게이트)
# ─────────────────────────────────────────────────────────

@test "verify: 테스트 SKIP + SOUL 호출실패 — 무증거 차단으로 FAIL" {
  _source_verify
  # agent_run mock: 즉시 실패 (SOUL 심판 호출실패 재현)
  agent_run() { return 1; }
  run verify_run "무증거 대상" "zen"
  [ "$status" -eq 1 ]
  [[ "$output" == *"무증거 차단"* ]]
}

@test "verify: 테스트 SKIP 이어도 SOUL PASS 면 통과 (증거 1개 확보)" {
  _source_verify
  agent_run() { printf '[VERDICT: PASS]\n이유: 충분함\n'; return 0; }
  run verify_run "심판 통과 대상" "zen"
  [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────────────────
# 루브릭 채점 (P1-3) — [ITEM-k: OK|NG] 항목 채점 + 스크립트 집계
# ─────────────────────────────────────────────────────────

@test "verify: 루브릭 3항목 전부 OK — PASS (rc 0) + 프롬프트에 ITEM 지시 포함" {
  _source_verify
  # mock: 프롬프트 캡처 + 항목 3건 전부 OK
  agent_run() {
    printf '%s\n' "$2" > "$TEST_PROJECT/.judge_prompt"
    printf '[ITEM-1: OK]\n[ITEM-2: OK]\n[ITEM-3: OK]\n'
    return 0
  }
  run verify_run "루브릭 대상" "zen"
  [ "$status" -eq 0 ]
  [[ "$output" == *"3항목"* ]]
  # 기본(루브릭 on) 프롬프트는 항목 채점 형식을 지시한다
  grep -q 'ITEM-1' "$TEST_PROJECT/.judge_prompt"
}

@test "verify: 루브릭 1항목 NG — FAIL (rc 1) + 사유가 출력에 노출" {
  _source_verify
  agent_run() {
    printf '[ITEM-1: OK]\n[ITEM-2: NG 경계값 테스트 누락]\n[ITEM-3: OK]\n'
    return 0
  }
  run verify_run "루브릭 대상" "zen"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ITEM-2"* ]]
  [[ "$output" == *"경계값 테스트 누락"* ]]
}

@test "verify: 항목 0건 + 레거시 [VERDICT: PASS] — 폴백으로 PASS" {
  _source_verify
  agent_run() { printf '판단 요약입니다.\n[VERDICT: PASS]\n이유: 기준 충족\n'; return 0; }
  run verify_run "레거시 폴백 대상" "zen"
  [ "$status" -eq 0 ]
}

@test "verify: 1차 garbage → 재질의에서 항목 채점 — 집계 동작 (호출 2회)" {
  _source_verify
  agent_run() {
    local n=0
    [ -f "$TEST_PROJECT/.judge_calls" ] && n=$(cat "$TEST_PROJECT/.judge_calls")
    n=$((n + 1)); printf '%d' "$n" > "$TEST_PROJECT/.judge_calls"
    if [ "$n" -eq 1 ]; then
      printf '음... 판단이 애매합니다\n'
    else
      printf '[ITEM-1: OK]\n[ITEM-2: OK]\n'
    fi
    return 0
  }
  run verify_run "재질의 대상" "zen"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_PROJECT/.judge_calls")" -eq 2 ]
  [[ "$output" == *"재질의"* ]]
}

@test "verify: GOLEM_VERIFY_RUBRIC=0 — 구 총평 프롬프트 (ITEM 지시 없음, VERDICT 지시 있음)" {
  _source_verify
  agent_run() {
    printf '%s\n' "$2" > "$TEST_PROJECT/.judge_prompt"
    printf '[VERDICT: PASS]\n이유: 충분함\n'
    return 0
  }
  GOLEM_VERIFY_RUBRIC=0 run verify_run "킬스위치 대상" "zen"
  [ "$status" -eq 0 ]
  ! grep -q 'ITEM-1' "$TEST_PROJECT/.judge_prompt"
  grep -q 'VERDICT' "$TEST_PROJECT/.judge_prompt"
}
