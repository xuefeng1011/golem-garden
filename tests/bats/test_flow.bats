#!/usr/bin/env bats
# test_flow.bats — Flow Engine (lib/flow-contract.sh, lib/flow-dag.sh, lib/flow.sh)
# Zen이 케이스를 작성한다 — 이 스텁은 호스트가 생성 (Zen 도구에 Write 부재).

load "test_helper"

setup() {
  TEST_PROJECT="$(mktemp -d "${TMPDIR:-/tmp}/flow-test.XXXXXX")"
  # 이 setup()이 test_helper의 setup()을 오버라이드하므로 GOLEM_ROOT를 직접 계산
  export GOLEM_ROOT
  GOLEM_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export GOLEM_DIR="$TEST_PROJECT/.golem" GOLEM_PROJECT="$TEST_PROJECT"
  mkdir -p "$GOLEM_DIR"
  source "${GOLEM_ROOT}/lib/flow.sh"

  # agent_run mock — 호출 횟수 추적용 카운터 파일
  agent_run() {
    local soul="$1" task="$2"
    echo "mock:$soul:$task"
    local count_file="$TEST_PROJECT/.agent_call_count"
    if [ -f "$count_file" ]; then
      local cnt
      cnt=$(cat "$count_file")
      printf '%d' "$((cnt + 1))" > "$count_file"
    else
      printf '1' > "$count_file"
    fi
    return "${MOCK_AGENT_RC:-0}"
  }
}

teardown() {
  rm -rf "$TEST_PROJECT"
}

_mk_steps() {
  cat > "$TEST_PROJECT/steps.json"
}

# ───────────────────────────────────────────────────────────────────────────────
# 1. flow_create — flow_id 반환 + state.json 생성 + step에 status:pending 주입
# ───────────────────────────────────────────────────────────────────────────────

@test "flow: create — flow_id 반환 및 state.json 생성" {
  _mk_steps <<'EOF'
[
  {
    "id": "step1",
    "soul": "zen",
    "task": "test task",
    "deps": []
  }
]
EOF

  run flow_create "test goal" "$TEST_PROJECT/steps.json"
  [ "$status" -eq 0 ]

  local flow_id="$output"
  [ -n "$flow_id" ]
  [ -f "${FLOW_DIR}/${flow_id}/state.json" ]

  # state.json에 status:pending 주입 확인
  grep -q '"status":"pending"' "${FLOW_DIR}/${flow_id}/state.json"
}

@test "flow: create — step에 status:pending 자동 주입" {
  _mk_steps <<'EOF'
[
  {
    "id": "s1",
    "soul": "alpha",
    "task": "task1",
    "deps": []
  },
  {
    "id": "s2",
    "soul": "beta",
    "task": "task2",
    "deps": ["s1"]
  }
]
EOF

  run flow_create "multi step" "$TEST_PROJECT/steps.json"
  [ "$status" -eq 0 ]

  local flow_id="$output"
  local state="${FLOW_DIR}/${flow_id}/state.json"

  # 두 step 모두 pending 상태 (grep -c는 라인 수라 단일 라인 JSON에 부적합 —
  # _fc_steps_lines로 step당 1줄 정규화 후 카운트)
  [ "$(_fc_steps_lines < "$state" | grep -c '"status":"pending"')" -eq 2 ]
}

# ───────────────────────────────────────────────────────────────────────────────
# 2. flow_validate — 사이클(a→b→a) 검출 → 비-0 종료
# ───────────────────────────────────────────────────────────────────────────────

@test "flow: validate — 사이클 감지(a→b→a) 실패" {
  _mk_steps <<'EOF'
[
  {
    "id": "a",
    "soul": "zen",
    "task": "task_a",
    "deps": ["b"]
  },
  {
    "id": "b",
    "soul": "zen",
    "task": "task_b",
    "deps": ["a"]
  }
]
EOF

  run flow_create "cyclic" "$TEST_PROJECT/steps.json"
  [ "$status" -eq 1 ]
}

@test "flow: validate — 정상 DAG 통과" {
  _mk_steps <<'EOF'
[
  {
    "id": "a",
    "soul": "zen",
    "task": "task_a",
    "deps": []
  },
  {
    "id": "b",
    "soul": "zen",
    "task": "task_b",
    "deps": ["a"]
  },
  {
    "id": "c",
    "soul": "zen",
    "task": "task_c",
    "deps": ["b"]
  }
]
EOF

  run flow_create "linear" "$TEST_PROJECT/steps.json"
  [ "$status" -eq 0 ]

  local flow_id="$output"
  run flow_validate "${FLOW_DIR}/${flow_id}/state.json"
  [ "$status" -eq 0 ]
}

# ───────────────────────────────────────────────────────────────────────────────
# 3. flow_next_ready — 토폴로지: deps 미충족 step 미출력, 충족 시 출력
# ───────────────────────────────────────────────────────────────────────────────

@test "flow: next_ready — deps 미충족 step 미출력" {
  _mk_steps <<'EOF'
[
  {
    "id": "s1",
    "soul": "zen",
    "task": "task1",
    "deps": []
  },
  {
    "id": "s2",
    "soul": "zen",
    "task": "task2",
    "deps": ["s1"]
  },
  {
    "id": "s3",
    "soul": "zen",
    "task": "task3",
    "deps": ["s2"]
  }
]
EOF

  run flow_create "linear flow" "$TEST_PROJECT/steps.json"
  local flow_id="$output"
  local state="${FLOW_DIR}/${flow_id}/state.json"

  # 초기 상태: s1만 ready (deps 없음)
  run flow_next_ready "$state"
  [ "$status" -eq 0 ]
  [ "$output" = "s1" ]

  # s1을 done으로 변경
  flow_set_step_status "$state" "s1" "done"

  # 이제 s2가 ready (s1이 done)
  run flow_next_ready "$state"
  [ "$status" -eq 0 ]
  [ "$output" = "s2" ]

  # s3은 여전히 not ready (s2가 pending)
  ! echo "$output" | grep -q "s3"
}

@test "flow: next_ready — 모든 deps done 시 step 출력" {
  _mk_steps <<'EOF'
[
  {
    "id": "s1",
    "soul": "zen",
    "task": "task1",
    "deps": []
  },
  {
    "id": "s2",
    "soul": "zen",
    "task": "task2",
    "deps": ["s1"]
  }
]
EOF

  run flow_create "two steps" "$TEST_PROJECT/steps.json"
  local flow_id="$output"
  local state="${FLOW_DIR}/${flow_id}/state.json"

  flow_set_step_status "$state" "s1" "done"

  run flow_next_ready "$state"
  [ "$status" -eq 0 ]
  grep -q "s2" <<< "$output"
}

# ───────────────────────────────────────────────────────────────────────────────
# 4. 병렬 그룹: deps 없는 step 2개 → 둘 다 동시에 ready
# ───────────────────────────────────────────────────────────────────────────────

@test "flow: parallel — deps 없는 step 2개 모두 ready" {
  _mk_steps <<'EOF'
[
  {
    "id": "p1",
    "soul": "zen",
    "task": "parallel_task_1",
    "deps": []
  },
  {
    "id": "p2",
    "soul": "zen",
    "task": "parallel_task_2",
    "deps": []
  },
  {
    "id": "join",
    "soul": "zen",
    "task": "join_task",
    "deps": ["p1", "p2"]
  }
]
EOF

  run flow_create "parallel flow" "$TEST_PROJECT/steps.json"
  local flow_id="$output"
  local state="${FLOW_DIR}/${flow_id}/state.json"

  # p1, p2 모두 deps 없으므로 모두 ready
  run flow_next_ready "$state"
  [ "$status" -eq 0 ]
  grep -q "p1" <<< "$output"
  grep -q "p2" <<< "$output"

  # join은 not ready (둘 다 pending)
  ! grep -q "join" <<< "$output"
}

# ───────────────────────────────────────────────────────────────────────────────
# 5. soul="" — deps가 유실되지 않음 (US(0x1f) 구분자 회귀)
# ───────────────────────────────────────────────────────────────────────────────

@test "flow: empty soul — deps 유실 회귀" {
  _mk_steps <<'EOF'
[
  {
    "id": "host_step",
    "soul": "",
    "task": "host_task",
    "deps": []
  },
  {
    "id": "follow",
    "soul": "zen",
    "task": "follow_task",
    "deps": ["host_step"]
  }
]
EOF

  run flow_create "empty soul" "$TEST_PROJECT/steps.json"
  [ "$status" -eq 0 ]

  local flow_id="$output"
  local state="${FLOW_DIR}/${flow_id}/state.json"

  # host_step 실행(HOST: prefix 출력)
  flow_set_step_status "$state" "host_step" "done"

  # follow가 ready인지 확인
  run flow_next_ready "$state"
  [ "$status" -eq 0 ]
  grep -q "follow" <<< "$output"
}

# ───────────────────────────────────────────────────────────────────────────────
# 6. retry 한계: MOCK_AGENT_RC=1 + retry=1 → agent_run 2회 호출 후 failed
# ───────────────────────────────────────────────────────────────────────────────

@test "flow: retry — 실패 후 재시도(retry=1), 2회 호출 후 failed" {
  _mk_steps <<'EOF'
[
  {
    "id": "retry_step",
    "soul": "zen",
    "task": "failing_task",
    "deps": [],
    "retry": 1,
    "on_fail": "abort"
  }
]
EOF

  run flow_create "retry flow" "$TEST_PROJECT/steps.json"
  local flow_id="$output"

  # mock을 실패 반환하도록 설정
  export MOCK_AGENT_RC=1

  # 카운터 초기화
  printf '0' > "$TEST_PROJECT/.agent_call_count"

  # flow_step_run 실행
  run flow_step_run "$flow_id" "retry_step"
  [ "$status" -ne 0 ]

  # agent_run이 2회 호출됨 (초기 + 1회 재시도)
  local count
  count=$(cat "$TEST_PROJECT/.agent_call_count")
  [ "$count" -eq 2 ]

  # step 상태 확인
  local state="${FLOW_DIR}/${flow_id}/state.json"
  grep -q '"id":"retry_step"[^}]*"status":"failed"' "$state"
}

# ───────────────────────────────────────────────────────────────────────────────
# 7. 승인 게이트: approval=true → flow_run이 waiting_approval로 중단
#    flow_approve 후 재실행 시 완주(completed)
# ───────────────────────────────────────────────────────────────────────────────

@test "flow: approval — approval=true step은 waiting_approval로 중단" {
  _mk_steps <<'EOF'
[
  {
    "id": "pre",
    "soul": "zen",
    "task": "pre_task",
    "deps": []
  },
  {
    "id": "gate",
    "soul": "zen",
    "task": "gate_task",
    "deps": ["pre"],
    "approval": true
  },
  {
    "id": "post",
    "soul": "zen",
    "task": "post_task",
    "deps": ["gate"]
  }
]
EOF

  run flow_create "approval flow" "$TEST_PROJECT/steps.json"
  local flow_id="$output"
  local state="${FLOW_DIR}/${flow_id}/state.json"

  # flow_run 실행 — approval에서 중단
  export MOCK_AGENT_RC=0
  flow_run "$flow_id"

  # pre는 done, gate는 waiting_approval, post는 pending
  grep -q '"id":"pre"[^}]*"status":"done"' "$state"
  grep -q '"id":"gate"[^}]*"status":"waiting_approval"' "$state"
  grep -q '"id":"post"[^}]*"status":"pending"' "$state"

  # flow 상태는 여전히 pending (완료하지 않음)
  local json
  json=$(tr -d '\n\r' < "$state")
  printf '%s' "$json" | grep -q '"status":"pending"'
}

@test "flow: approve — 승인 후 재실행 시 complete" {
  _mk_steps <<'EOF'
[
  {
    "id": "step1",
    "soul": "zen",
    "task": "task1",
    "deps": []
  },
  {
    "id": "gated",
    "soul": "zen",
    "task": "gate_task",
    "deps": ["step1"],
    "approval": true
  }
]
EOF

  run flow_create "simple approval" "$TEST_PROJECT/steps.json"
  local flow_id="$output"
  local state="${FLOW_DIR}/${flow_id}/state.json"

  export MOCK_AGENT_RC=0

  # 첫 실행 — gate에서 중단
  flow_run "$flow_id"
  grep -q '"status":"waiting_approval"' "$state"

  # 승인
  flow_approve "$flow_id" "gated"

  # 재실행 — 완주
  flow_run "$flow_id"

  # gated가 done이어야 함
  grep -q '"id":"gated"[^}]*"status":"done"' "$state"

  # flow는 completed
  local json
  json=$(tr -d '\n\r' < "$state")
  printf '%s' "$json" | grep -q '"status":"completed"'
}

# ───────────────────────────────────────────────────────────────────────────────
# 8. on_fail — goto:X와 continue 처리
# ───────────────────────────────────────────────────────────────────────────────

@test "flow: on_fail=goto:X — 실패 시 X 상태를 pending으로 리셋" {
  _mk_steps <<'EOF'
[
  {
    "id": "fail_step",
    "soul": "zen",
    "task": "failing_task",
    "deps": [],
    "on_fail": "goto:recovery"
  },
  {
    "id": "recovery",
    "soul": "zen",
    "task": "recovery_task",
    "deps": []
  }
]
EOF

  run flow_create "goto flow" "$TEST_PROJECT/steps.json"
  local flow_id="$output"
  local state="${FLOW_DIR}/${flow_id}/state.json"

  export MOCK_AGENT_RC=1

  flow_step_run "$flow_id" "fail_step"

  # fail_step는 failed
  grep -q '"id":"fail_step"[^}]*"status":"failed"' "$state"

  # recovery는 pending으로 리셋됨
  grep -q '"id":"recovery"[^}]*"status":"pending"' "$state"
}

@test "flow: on_fail=continue — 실패 후 플로우 진행, 최종 failed" {
  _mk_steps <<'EOF'
[
  {
    "id": "fail1",
    "soul": "zen",
    "task": "task1",
    "deps": [],
    "on_fail": "continue"
  },
  {
    "id": "succ",
    "soul": "zen",
    "task": "task2",
    "deps": ["fail1"]
  }
]
EOF

  run flow_create "continue flow" "$TEST_PROJECT/steps.json"
  local flow_id="$output"
  local state="${FLOW_DIR}/${flow_id}/state.json"

  export MOCK_AGENT_RC=1

  # fail1 실행 — continue이므로 rc=0으로 처리
  flow_step_run "$flow_id" "fail1"

  # fail1은 failed
  grep -q '"id":"fail1"[^}]*"status":"failed"' "$state"

  # 다음 step(succ)를 수동으로 실행
  export MOCK_AGENT_RC=0
  flow_step_run "$flow_id" "succ"

  # flow_run 전체 실행 시 최종 상태가 failed
  flow_run "$flow_id"

  local json
  json=$(tr -d '\n\r' < "$state")
  printf '%s' "$json" | grep -q '"status":"failed"'
}

# ───────────────────────────────────────────────────────────────────────────────
# 9. flow_set_step_status — 플로우 레벨 status 오염 방지
# ───────────────────────────────────────────────────────────────────────────────

@test "flow: set_step_status — 플로우 레벨 status 오염 안함" {
  _mk_steps <<'EOF'
[
  {
    "id": "s1",
    "soul": "zen",
    "task": "task1",
    "deps": []
  },
  {
    "id": "s2",
    "soul": "zen",
    "task": "task2",
    "deps": ["s1"]
  }
]
EOF

  run flow_create "isolation test" "$TEST_PROJECT/steps.json"
  local flow_id="$output"
  local state="${FLOW_DIR}/${flow_id}/state.json"

  # flow 초기 상태 확인
  local initial_json
  initial_json=$(tr -d '\n\r' < "$state")
  initial_status=$(printf '%s' "$initial_json" | grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:"\|"//g')
  [ "$initial_status" = "pending" ]

  # step s1의 status를 done으로 변경
  flow_set_step_status "$state" "s1" "done"

  # flow 레벨 status는 여전히 pending
  local after_json
  after_json=$(tr -d '\n\r' < "$state")
  after_status=$(printf '%s' "$after_json" | grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:"\|"//g')
  [ "$after_status" = "pending" ]

  # s1은 done이어야 함
  grep -q '"id":"s1"[^}]*"status":"done"' "$state"
}

# ───────────────────────────────────────────────────────────────────────────────
# 10. 리뷰 후속 회귀 (2026-06-13 code-review HIGH 1~3)
# ───────────────────────────────────────────────────────────────────────────────

@test "flow: abort — 같은 ready 그룹의 잔여 step 실행 중단 (HIGH-1)" {
  _mk_steps <<'JSON'
[
  {"id": "boom", "soul": "zen", "task": "fails", "deps": [], "retry": 0, "on_fail": "abort"},
  {"id": "other", "soul": "zen", "task": "parallel", "deps": [], "retry": 0, "on_fail": "abort"}
]
JSON
  run flow_create "abort group" "$TEST_PROJECT/steps.json"
  local flow_id="$output"
  local state="${FLOW_DIR}/${flow_id}/state.json"

  export MOCK_AGENT_RC=1
  flow_run "$flow_id" || true

  # boom은 failed, 같은 그룹의 other는 실행되지 않고 pending 유지
  grep -q '"id":"boom"[^}]*"status":"failed"' "$state"
  grep -q '"id":"other"[^}]*"status":"pending"' "$state"
}

@test "flow: waiting_approval만 잔존 시 completed 오기록 금지 (HIGH-2)" {
  _mk_steps <<'JSON'
[
  {"id": "gate", "soul": "zen", "task": "needs ok", "deps": [], "retry": 0, "approval": true, "on_fail": "abort"}
]
JSON
  run flow_create "approval only" "$TEST_PROJECT/steps.json"
  local flow_id="$output"
  local state="${FLOW_DIR}/${flow_id}/state.json"

  export MOCK_AGENT_RC=0
  flow_run "$flow_id"   # gate → waiting_approval, 중단
  flow_run "$flow_id"   # 승인 없이 재진입 — completed로 빠지면 안 됨

  grep -q '"id":"gate"[^}]*"status":"waiting_approval"' "$state"
  local head_status
  head_status=$(sed 's/"steps".*//' "$state" | grep -o '"status":"[a-z]*"')
  [ "$head_status" = '"status":"pending"' ]
}

@test "flow: goto 자기참조 — failed target이면 abort 격하, 재소환 폭주 금지 (HIGH-3)" {
  _mk_steps <<'JSON'
[
  {"id": "loopy", "soul": "zen", "task": "self goto", "deps": [], "retry": 0, "on_fail": "goto:loopy"}
]
JSON
  run flow_create "goto self" "$TEST_PROJECT/steps.json"
  local flow_id="$output"
  local state="${FLOW_DIR}/${flow_id}/state.json"

  export MOCK_AGENT_RC=1
  printf '0' > "$TEST_PROJECT/.agent_call_count"
  flow_run "$flow_id" || true

  # 폭주 금지: agent_run 1회만 (실패 → 자기 자신 failed → goto 격하 abort)
  [ "$(cat "$TEST_PROJECT/.agent_call_count")" -eq 1 ]
  local head_status
  head_status=$(sed 's/"steps".*//' "$state" | grep -o '"status":"[a-z]*"')
  [ "$head_status" = '"status":"failed"' ]
}

# ───────────────────────────────────────────────────────────────────────────────
# 18. 파이프라인: input 타입 + 단계 출력 + {{id}} 데이터 전달
# ───────────────────────────────────────────────────────────────────────────────

@test "flow: input 노드 — task값이 곧 출력" {
  _mk_steps <<'JSON'
[{"id":"in1","soul":"","task":"주제 텍스트","deps":[],"type":"input"}]
JSON
  run flow_create "input flow" "$TEST_PROJECT/steps.json"
  local flow_id="$output"
  local state="${FLOW_DIR}/${flow_id}/state.json"
  flow_step_run "$flow_id" in1
  [ "$(flow_step_output "$state" in1)" = "주제 텍스트" ]
  grep -q '"id":"in1"[^}]*"status":"done"' "$state"
}

@test "flow: set/get step output — add-or-replace + 이스케이프" {
  _mk_steps <<'JSON'
[{"id":"s1","soul":"zen","task":"t","deps":[],"type":"agent"}]
JSON
  run flow_create "out" "$TEST_PROJECT/steps.json"
  local state="${FLOW_DIR}/${output}/state.json"
  flow_set_step_output "$state" s1 'line1
line2 "quoted"'
  # 저장된 output 에 이스케이프된 개행/따옴표 포함
  run flow_step_output "$state" s1
  [[ "$output" == *'line1\nline2'* ]]
  [[ "$output" == *'\"quoted\"'* ]]
  # 재기록(replace) — 중복 안 생김
  flow_set_step_output "$state" s1 "second"
  [ "$(_fc_steps_lines < "$state" | grep -F '"id":"s1"' | grep -oc '"output"')" -eq 1 ]
}

@test "flow: {{id}} 치환 — 상류 출력이 하류 task로 주입" {
  _mk_steps <<'JSON'
[{"id":"in1","soul":"","task":"고양이","deps":[],"type":"input"},
 {"id":"a1","soul":"zen","task":"요약: {{in1}}","deps":["in1"],"type":"agent"}]
JSON
  run flow_create "chain" "$TEST_PROJECT/steps.json"
  local flow_id="$output"
  local state="${FLOW_DIR}/${flow_id}/state.json"
  # in1 실행 → 출력 설정
  flow_step_run "$flow_id" in1
  # mock agent_run: 받은 task를 출력으로
  agent_run() { echo "GOT:$2"; echo "<usage> run=11111111-2222-4333-8444-555555555555"; return 0; }
  run flow_step_run "$flow_id" a1
  [[ "$output" == *"GOT:요약: 고양이"* ]]
}

@test "flow: 미존재 {{id}} 는 그대로 보존" {
  _mk_steps <<'JSON'
[{"id":"a1","soul":"zen","task":"ref {{ghost}}","deps":[],"type":"agent"}]
JSON
  run flow_create "noref" "$TEST_PROJECT/steps.json"
  local state="${FLOW_DIR}/${output}/state.json"
  run _flow_subst "$state" "ref {{ghost}}"
  [ "$output" = "ref {{ghost}}" ]
}
