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
  # (예시는 숫자 대신 '번호' 자리표시자를 쓴다 — 에코 방어, 아래 별도 테스트 참조)
  grep -q 'ITEM-' "$TEST_PROJECT/.judge_prompt"
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

# ─────────────────────────────────────────────────────────
# B-5 — VERIFY_RUBRIC_ITEMS 사전 계약 채점 (분해 시점 확정 항목)
# ─────────────────────────────────────────────────────────

@test "B-5 verify: VERIFY_RUBRIC_ITEMS 설정 — 프롬프트에 사전 계약 항목 그대로 주입" {
  _source_verify
  agent_run() {
    printf '%s\n' "$2" > "$TEST_PROJECT/.judge_prompt"
    printf '[ITEM-1: OK]\n[ITEM-2: OK]\n'
    return 0
  }
  VERIFY_RUBRIC_ITEMS="a.sh 존재 확인
bash tests/bats/run.sh 가 exit 0" run verify_run "대상" "zen"
  [ "$status" -eq 0 ]
  grep -q "분해 시점에 합의된 채점 항목" "$TEST_PROJECT/.judge_prompt"
  grep -q "a.sh 존재 확인" "$TEST_PROJECT/.judge_prompt"
  grep -q "bash tests/bats/run.sh 가 exit 0" "$TEST_PROJECT/.judge_prompt"
}

@test "B-5 verify: 사전 계약 항목 전부 채점 — PASS" {
  _source_verify
  agent_run() { printf '[ITEM-1: OK]\n[ITEM-2: OK]\n'; return 0; }
  VERIFY_RUBRIC_ITEMS="항목1
항목2" run verify_run "대상" "zen"
  [ "$status" -eq 0 ]
}

@test "B-5 verify: 사전 계약 항목 수 < 실제 채점 건수 — 누락 항목 NG 로 합성해 FAIL" {
  _source_verify
  # 항목 2개를 주입했는데 SOUL 이 1개만 채점 — ITEM-2 누락
  agent_run() { printf '[ITEM-1: OK]\n'; return 0; }
  VERIFY_RUBRIC_ITEMS="항목1
항목2" run verify_run "대상" "zen"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ITEM-2"* ]]
  [[ "$output" == *"채점 누락"* ]]
}

@test "B-5 verify: VERIFY_RUBRIC_ITEMS 미설정 — 기존 자체 분해 프롬프트 그대로 (회귀)" {
  _source_verify
  agent_run() {
    printf '%s\n' "$2" > "$TEST_PROJECT/.judge_prompt"
    printf '[ITEM-1: OK]\n[ITEM-2: OK]\n'
    return 0
  }
  run verify_run "대상" "zen"
  [ "$status" -eq 0 ]
  grep -q "검증 대상의 성공 기준을 검증 가능한 구체 항목 2~6개로 분해하세요" "$TEST_PROJECT/.judge_prompt"
  ! grep -q "분해 시점에 합의된 채점 항목" "$TEST_PROJECT/.judge_prompt"
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

@test "verify: 루브릭 위반 — ITEM NG 존재 + 상충하는 [VERDICT: PASS] 동시 존재 — 항목이 우선(FAIL)" {
  _source_verify
  # 심판이 항목별로는 NG를 매겼지만 총평 마커는 실수로 PASS를 남긴 경우 —
  # 집계는 VERDICT 를 보지 않고 항목만 보므로 항목이 이겨야 한다 (FAIL).
  agent_run() {
    printf '[ITEM-1: OK]\n[ITEM-2: NG 경계값 테스트 근거 없음]\n[VERDICT: PASS]\n'
    return 0
  }
  run verify_run "루브릭 우선 대상" "zen"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ITEM-2"* ]]
  [[ "$output" == *"경계값 테스트 근거 없음"* ]]
}

@test "verify: 프롬프트 예시 에코 방어 — 번호 자리표시자 라인만 에코 + [VERDICT: PASS] — phantom item 없이 레거시 폴백 PASS" {
  _source_verify
  # 심판이 프롬프트의 형식 예시(번호 자리표시자)를 그대로 베껴 쓰고 실제 채점은
  # 하지 않은 채 총평 마커만 붙인 최악의 경우 — 자리표시자는 숫자가 아니므로
  # 집계 정규식([0-9]+)에 걸리지 않아 phantom item 이 생기지 않고, 레거시
  # [VERDICT:] 폴백으로 정상 PASS 되어야 한다.
  agent_run() {
    printf '[ITEM-번호: OK]\n[ITEM-번호: NG <한 줄 사유>]\n[VERDICT: PASS]\n'
    return 0
  }
  run verify_run "에코 방어 대상" "zen"
  [ "$status" -eq 0 ]
}

@test "verify: 루브릭 프롬프트 예시는 숫자 대신 '번호' 자리표시자 사용 (에코 방어 원천 차단)" {
  _source_verify
  agent_run() {
    printf '%s\n' "$2" > "$TEST_PROJECT/.judge_prompt"
    printf '[ITEM-1: OK]\n'
    return 0
  }
  run verify_run "프롬프트 형식 검증 대상" "zen"
  # 실제 지시문/예시에 'ITEM-번호' 자리표시자가 있어야 하고, 숫자 예시(ITEM-1 등)는
  # 프롬프트 본문에 없어야 한다 (에코 시 집계 정규식에 걸리지 않도록).
  grep -q 'ITEM-번호' "$TEST_PROJECT/.judge_prompt"
  ! grep -q 'ITEM-1' "$TEST_PROJECT/.judge_prompt"
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

# ─────────────────────────────────────────────────────────
# pytest 러너 폴백 체인 (P0-3) — uv > .venv > PATH python
# ─────────────────────────────────────────────────────────

@test "verify: pytest 러너 — uv 존재 시 uv run pytest" {
  _source_verify
  local fake_bin="$TEST_PROJECT/fakebin"
  mkdir -p "$fake_bin"
  printf '#!/bin/sh\nexit 0\n' > "$fake_bin/uv"; chmod +x "$fake_bin/uv"
  # Windows 식 'C:/...' 경로는 콜론이 PATH 구분자로 오파싱됨 → POSIX 형태로 변환
  local fake_posix; fake_posix=$(cd "$fake_bin" && pwd)
  local out
  out=$(PATH="$fake_posix:$PATH" _verify_pytest_runner "$TEST_PROJECT/gw")
  [ "$out" = "uv run pytest" ]
}

@test "verify: pytest 러너 — uv 없음 + .venv 존재 시 venv python" {
  _source_verify
  local gw="$TEST_PROJECT/gw"
  mkdir -p "$gw/.venv/Scripts"
  printf '#!/bin/sh\nexit 0\n' > "$gw/.venv/Scripts/python.exe"
  local fake_bin="$TEST_PROJECT/fakebin-nouv"
  mkdir -p "$fake_bin"
  local out
  out=$(PATH="$fake_bin" _verify_pytest_runner "$gw")
  [ "$out" = "$gw/.venv/Scripts/python.exe -m pytest" ]
}

@test "verify: pytest 러너 — uv/venv 없음 시 PATH python 폴백" {
  _source_verify
  local fake_bin="$TEST_PROJECT/fakebin-py"
  mkdir -p "$fake_bin"
  printf '#!/bin/sh\nexit 0\n' > "$fake_bin/python"; chmod +x "$fake_bin/python"
  local fake_posix; fake_posix=$(cd "$fake_bin" && pwd)
  local out
  out=$(PATH="$fake_posix" _verify_pytest_runner "$TEST_PROJECT/no-such-gw")
  [ "$out" = "python -m pytest" ]
}
