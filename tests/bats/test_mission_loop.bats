#!/usr/bin/env bats
# test_mission_loop.bats — lib/mission-loop.sh (forge mission run 결정론 루프, P1-6)
#
# agent_run/verify_run/error_retry/budget_record 를 bats 함수 재정의로 mock —
# _mission_loop_deps 는 command -v 선확인이라 mock 이 있으면 실제 lib 을 소싱하지 않는다.

load "test_helper"

setup() {
  TEST_PROJECT="$(mktemp -d "${TMPDIR:-/tmp}/mloop-test.XXXXXX")"
  export GOLEM_ROOT
  GOLEM_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export GOLEM_DIR="$TEST_PROJECT/.golem" GOLEM_PROJECT="$TEST_PROJECT"
  mkdir -p "$GOLEM_DIR"
  source "${GOLEM_ROOT}/lib/mission-loop.sh"

  # ── mocks (호출 시점 참조 계약) ──────────────────────────────
  agent_run() {
    _bump "$TEST_PROJECT/.agent_calls"
    echo "mock-agent:$1 tokens_out=1000"
    return "${MOCK_AGENT_RC:-0}"
  }
  verify_run() {
    _bump "$TEST_PROJECT/.verify_calls"
    echo "verify author=${VERIFY_AUTHOR_SOUL:-none}"
    if [ "${MOCK_VERIFY_RC:-0}" -ne 0 ]; then
      if [ "${MOCK_VERIFY_SAME_REASON:-0}" -eq 1 ]; then
        echo "[VERDICT: FAIL] 이유: 항상 같은 사유"
      else
        echo "[VERDICT: FAIL] 이유: 사유-$(cat "$TEST_PROJECT/.verify_calls")"
      fi
    fi
    return "${MOCK_VERIFY_RC:-0}"
  }
  error_retry() { echo "retry-prompt(${4}): ${2}"; return 0; }
  budget_record() { echo "${MOCK_BUDGET_OUT:-}"; return 0; }
  soul_find_best_match() { echo "ryn"; }
}

teardown() {
  rm -rf "$TEST_PROJECT"
}

_bump() {
  local f="$1" c=0
  [ -f "$f" ] && c=$(cat "$f")
  printf '%d' "$((c + 1))" > "$f"
}

_mk_mission() {
  # 2-태스크 미션 생성 → id 를 stdout 으로
  local id
  id=$(mission_init "테스트 목표" "모든 태스크 done + 검증 PASS" "" "")
  mission_set_tasks "$id" "태스크 A|태스크 B" >/dev/null
  echo "$id"
}

@test "mission-loop: 정상 완주 — COMPLETE 센티널 + completed + loop.json 정리" {
  local id; id=$(_mk_mission)

  run mission_run "$id" ryn zen
  [ "$status" -eq 0 ]
  [[ "$output" == *"<promise>COMPLETE</promise>"* ]]
  grep -q '"status":"completed"' "${GOLEM_DIR}/missions/${id}/state.json"
  [ ! -f "${GOLEM_DIR}/missions/${id}/loop.json" ]
  # 태스크 2건 각 1회 소환
  [ "$(cat "$TEST_PROJECT/.agent_calls")" -eq 2 ]
  [ "$(cat "$TEST_PROJECT/.verify_calls")" -eq 1 ]
}

@test "mission-loop: 태스크 attempt 상한 — 3회 실패 시 failed 정지 (rc=1)" {
  local id; id=$(_mk_mission)

  MOCK_AGENT_RC=1 run mission_run "$id" ryn zen
  [ "$status" -eq 1 ]
  [[ "$output" == *"3회 연속 실패"* ]]
  # 첫 태스크만 3회 시도 후 정지
  [ "$(cat "$TEST_PROJECT/.agent_calls")" -eq 3 ]
  grep -q '"status":"failed"' "${GOLEM_DIR}/missions/${id}/state.json"
}

@test "mission-loop: 검증 3사이클 실패 — 정지 조건 (c) (rc=4)" {
  local id; id=$(_mk_mission)

  # verify 실패 사유가 사이클마다 달라 STUCK 은 미발동 — 순수 사이클 상한 검증
  MOCK_VERIFY_RC=1 run mission_run "$id" ryn zen
  [ "$status" -eq 4 ]
  [[ "$output" == *"3사이클 실패"* ]]
  [ "$(cat "$TEST_PROJECT/.verify_calls")" -eq 3 ]
  # loop.json 에 cycles 기록 유지 (재계획 재개용)
  grep -q '"cycles":3' "${GOLEM_DIR}/missions/${id}/loop.json"
}

@test "mission-loop: 스턱 디텍터 — 동일 실패 서명 2연속이면 STUCK (rc=3)" {
  local id; id=$(_mk_mission)

  MOCK_VERIFY_RC=1 MOCK_VERIFY_SAME_REASON=1 run mission_run "$id" ryn zen
  [ "$status" -eq 3 ]
  [[ "$output" == *"STUCK"* ]]
  # 사이클 상한(3) 전에 정지 — 2번째 verify 에서 서명 동일 감지
  [ "$(cat "$TEST_PROJECT/.verify_calls")" -eq 2 ]
}

@test "mission-loop: BUDGET_EXCEEDED — 즉시 정지 + 태스크 pending 복귀 (rc=2)" {
  local id; id=$(_mk_mission)

  MOCK_BUDGET_OUT=BUDGET_EXCEEDED run mission_run "$id" ryn zen
  [ "$status" -eq 2 ]
  [[ "$output" == *"BUDGET_EXCEEDED"* ]]
  # 소환 1회 후 정지, 태스크는 pending 복귀 (done 0건)
  [ "$(cat "$TEST_PROJECT/.agent_calls")" -eq 1 ]
  ! grep -q '"status":"done"' "${GOLEM_DIR}/missions/${id}/state.json"
}

@test "mission-loop: BUDGET_STAGNATING — 수확체감 정지 (rc=2)" {
  local id; id=$(_mk_mission)

  MOCK_BUDGET_OUT=BUDGET_STAGNATING run mission_run "$id" ryn zen
  [ "$status" -eq 2 ]
  [[ "$output" == *"BUDGET_STAGNATING"* ]]
}

@test "mission-loop: verify 에 author(VERIFY_AUTHOR_SOUL) 전달 — 가드 배선 확인" {
  local id; id=$(_mk_mission)

  run mission_run "$id" ryn zen
  [ "$status" -eq 0 ]
  [[ "$output" == *"verify author=ryn"* ]]
}

@test "mission-loop: 검증 실패 피드백이 다음 사이클 태스크 프롬프트에 주입" {
  local id; id=$(_mk_mission)

  # 1사이클 실패 후 2사이클에서 성공하도록 — verify_calls 기반 분기
  verify_run() {
    _bump "$TEST_PROJECT/.verify_calls"
    echo "verify author=${VERIFY_AUTHOR_SOUL:-none}"
    if [ "$(cat "$TEST_PROJECT/.verify_calls")" -eq 1 ]; then
      echo "[VERDICT: FAIL] 이유: 경계값 검증 누락"
      return 1
    fi
    return 0
  }
  # agent mock 이 받은 프롬프트를 기록
  agent_run() {
    _bump "$TEST_PROJECT/.agent_calls"
    printf '%s\n' "$2" >> "$TEST_PROJECT/.prompts"
    echo "tokens_out=1000"
    return 0
  }

  run mission_run "$id" ryn zen
  [ "$status" -eq 0 ]
  grep -q "검증 실패 피드백" "$TEST_PROJECT/.prompts"
  grep -q "경계값 검증 누락" "$TEST_PROJECT/.prompts"
}

@test "mission-loop: 태스크 없는 미션 — set-tasks 안내 후 rc=1" {
  local id
  id=$(mission_init "빈 미션" "" "" "")

  run mission_run "$id" ryn zen
  [ "$status" -eq 1 ]
  [[ "$output" == *"set-tasks"* ]]
}

@test "mission-loop: 미존재 미션 — rc=1" {
  run mission_run "msn_9999999999_0" ryn zen
  [ "$status" -eq 1 ]
}

# ─────────────────────────────────────────────────────────
# C-2 — 스텝별 턴 예산 산정이 AGENT_MAX_TURNS_OVERRIDE 로 agent_run 에 전달되는지
# ─────────────────────────────────────────────────────────

@test "mission-loop: C-2 스텝 캡 — 산정치가 AGENT_MAX_TURNS_OVERRIDE 로 agent_run 에 전달" {
  local id; id=$(_mk_mission)
  # triage.sh 를 먼저 소싱해 _mission_loop_deps 의 지연 소싱(lazy source)이
  # 재실행되어 아래 mock 을 덮어쓰지 않게 한다 (command -v 선확인 계약).
  source "${GOLEM_ROOT}/lib/triage.sh"
  _triage_explore_files() { printf '%s\n' "lib/a.sh" "lib/b.sh"; }
  agent_run() {
    _bump "$TEST_PROJECT/.agent_calls"
    echo "$AGENT_MAX_TURNS_OVERRIDE" >> "$TEST_PROJECT/.override_calls"
    echo "mock-agent:$1 tokens_out=1000"
    return "${MOCK_AGENT_RC:-0}"
  }

  run mission_run "$id" ryn zen
  [ "$status" -eq 0 ]
  # rank junior(souls/ryn.md 실물) + est_files 2 → base 12 + 2*3 + 2 = 20
  [ "$(sed -n '1p' "$TEST_PROJECT/.override_calls")" = "20" ]
  [ "$(sed -n '2p' "$TEST_PROJECT/.override_calls")" = "20" ]
}

@test "mission-loop: C-2 GOLEM_TURN_BUDGET=0 → 산정 비활성, override 미전달(기존 동작)" {
  local id; id=$(_mk_mission)
  source "${GOLEM_ROOT}/lib/triage.sh"
  _triage_explore_files() { printf '%s\n' "lib/a.sh" "lib/b.sh"; }
  agent_run() {
    _bump "$TEST_PROJECT/.agent_calls"
    echo "[${AGENT_MAX_TURNS_OVERRIDE}]" >> "$TEST_PROJECT/.override_calls"
    echo "mock-agent:$1 tokens_out=1000"
    return "${MOCK_AGENT_RC:-0}"
  }

  GOLEM_TURN_BUDGET=0 run mission_run "$id" ryn zen
  [ "$status" -eq 0 ]
  [ "$(sed -n '1p' "$TEST_PROJECT/.override_calls")" = "[]" ]
}
