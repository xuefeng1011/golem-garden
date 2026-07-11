#!/usr/bin/env bats
# test_flow_parallel.bats — DAG ready 그룹 병렬 배치 실행 (GOLEM_FLOW_PARALLEL)
# lib/flow.sh 의 _flow_run_wave/_flow_build_batches/rank 게이트 회귀 테스트.
# mock agent_run 오버라이드 패턴은 test_flow.bats 를 미러 — 공유 카운터 파일
# 경합을 피하려고 soul/스텝별 마커 파일을 사용한다.

load "test_helper"

setup() {
  TEST_PROJECT="$(mktemp -d "${TMPDIR:-/tmp}/flow-par-test.XXXXXX")"
  export GOLEM_ROOT
  GOLEM_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export GOLEM_DIR="$TEST_PROJECT/.golem" GOLEM_PROJECT="$TEST_PROJECT"
  export GOLEM_FLOW_RETRY_BASE_SEC=0
  mkdir -p "$GOLEM_DIR/souls"
  source "${GOLEM_ROOT}/lib/flow.sh"

  agent_run() {
    echo "mock:$1:$2"
    return "${MOCK_AGENT_RC:-0}"
  }
}

teardown() {
  rm -rf "$TEST_PROJECT"
}

_mk_steps() {
  cat > "$TEST_PROJECT/steps.json"
}

# _mk_soul <name> <rank> — rank 게이트 테스트용 SOUL frontmatter 생성
_mk_soul() {
  local name="$1" rank="$2"
  cat > "$GOLEM_DIR/souls/${name}.md" <<SOULEOF
---
name: ${name}
role: worker
rank: ${rank}
---
Body
SOULEOF
}

# ───────────────────────────────────────────────────────────────────────────
# 1. 동시성 증명
# ───────────────────────────────────────────────────────────────────────────

@test "flow: parallel — 동시성 증명: 서로의 시작 마커를 관측 가능(GOLEM_FLOW_PARALLEL=2)" {
  _mk_steps <<'JSON'
[
  {"id":"p1","soul":"alpha","task":"t1","deps":[]},
  {"id":"p2","soul":"beta","task":"t2","deps":[]}
]
JSON
  run flow_create "concurrency proof" "$TEST_PROJECT/steps.json"
  local flow_id="$output"

  agent_run() {
    local soul="$1"
    : > "$TEST_PROJECT/.start.${soul}"
    local other waited=0
    case "$soul" in alpha) other=beta ;; beta) other=alpha ;; esac
    while [ ! -f "$TEST_PROJECT/.start.${other}" ] && [ "$waited" -lt 50 ]; do
      sleep 0.1
      waited=$((waited + 1))
    done
    [ -f "$TEST_PROJECT/.start.${other}" ] || return 1
    echo "ok:$soul"
    return 0
  }

  export GOLEM_FLOW_PARALLEL=2
  run flow_run "$flow_id"
  [ "$status" -eq 0 ]
  [ -f "$TEST_PROJECT/.start.alpha" ]
  [ -f "$TEST_PROJECT/.start.beta" ]
}

# ───────────────────────────────────────────────────────────────────────────
# 2. cap — 동시 실행 수가 상한을 넘지 않음
# ───────────────────────────────────────────────────────────────────────────

@test "flow: parallel — cap(GOLEM_FLOW_PARALLEL=2) 초과 동시 실행 없음" {
  _mk_steps <<'JSON'
[
  {"id":"c1","soul":"gamma","task":"t1","deps":[]},
  {"id":"c2","soul":"delta","task":"t2","deps":[]},
  {"id":"c3","soul":"epsilon","task":"t3","deps":[]}
]
JSON
  run flow_create "cap flow" "$TEST_PROJECT/steps.json"
  local flow_id="$output"

  agent_run() {
    local soul="$1"
    local running_dir="$TEST_PROJECT/.running"
    mkdir -p "$running_dir"
    : > "${running_dir}/${soul}"
    sleep 0.3
    ls "$running_dir" | wc -l >> "$TEST_PROJECT/.concurrency_log"
    sleep 0.2
    rm -f "${running_dir}/${soul}"
    echo "ok:$soul"
    return 0
  }

  export GOLEM_FLOW_PARALLEL=2
  run flow_run "$flow_id"
  [ "$status" -eq 0 ]

  local max
  max=$(sort -n "$TEST_PROJECT/.concurrency_log" | tail -1)
  [ "$max" -le 2 ]
}

# ───────────────────────────────────────────────────────────────────────────
# 3. abort 집계 — 형제를 죽이지 않고 전원 완주 후 판정
# ───────────────────────────────────────────────────────────────────────────

@test "flow: parallel — abort 집계: A 실패해도 B는 완주 + downstream 미실행" {
  _mk_steps <<'JSON'
[
  {"id":"A","soul":"a_soul","task":"fails","deps":[],"retry":0,"on_fail":"abort"},
  {"id":"B","soul":"b_soul","task":"slow ok","deps":[],"retry":0,"on_fail":"abort"},
  {"id":"down","soul":"c_soul","task":"downstream","deps":["A","B"],"retry":0,"on_fail":"abort"}
]
JSON
  run flow_create "abort agg" "$TEST_PROJECT/steps.json"
  local flow_id="$output"
  local state="${FLOW_DIR}/${flow_id}/state.json"

  agent_run() {
    local soul="$1"
    case "$soul" in
      a_soul) return 1 ;;
      b_soul) sleep 0.5; : > "$TEST_PROJECT/.b_done"; echo "b ok"; return 0 ;;
      *) echo "ok"; return 0 ;;
    esac
  }

  export GOLEM_FLOW_PARALLEL=2
  run flow_run "$flow_id"
  [ "$status" -eq 1 ]
  [ -f "$TEST_PROJECT/.b_done" ]
  grep -q '"id":"A"[^}]*"status":"failed"' "$state"
  grep -q '"id":"B"[^}]*"status":"done"' "$state"
  grep -q '"id":"down"[^}]*"status":"pending"' "$state"

  local head_status
  head_status=$(sed 's/"steps".*//' "$state" | grep -o '"status":"[a-z]*"')
  [ "$head_status" = '"status":"failed"' ]
}

# ───────────────────────────────────────────────────────────────────────────
# 4. on_fail=continue — 형제 실패해도 웨이브/다음 웨이브 중단 없음
# ───────────────────────────────────────────────────────────────────────────

@test "flow: parallel — on_fail=continue 형제 실패는 웨이브 중단 없이 다음 웨이브 진행" {
  _mk_steps <<'JSON'
[
  {"id":"c1","soul":"cfail","task":"fail","deps":[],"retry":0,"on_fail":"continue"},
  {"id":"c2","soul":"cok","task":"ok","deps":[],"retry":0,"on_fail":"abort"},
  {"id":"d1","soul":"dsoul1","task":"d1 task","deps":["c2"],"retry":0,"on_fail":"abort"},
  {"id":"d2","soul":"dsoul2","task":"d2 task","deps":["c2"],"retry":0,"on_fail":"abort"}
]
JSON
  run flow_create "continue next wave" "$TEST_PROJECT/steps.json"
  local flow_id="$output"
  local state="${FLOW_DIR}/${flow_id}/state.json"

  agent_run() {
    local soul="$1"
    case "$soul" in
      cfail) return 1 ;;
      *) echo "ok"; return 0 ;;
    esac
  }

  export GOLEM_FLOW_PARALLEL=2
  run flow_run "$flow_id"
  grep -q '"id":"c1"[^}]*"status":"failed"' "$state"
  grep -q '"id":"c2"[^}]*"status":"done"' "$state"
  grep -q '"id":"d1"[^}]*"status":"done"' "$state"
  grep -q '"id":"d2"[^}]*"status":"done"' "$state"
}

# ───────────────────────────────────────────────────────────────────────────
# 5. 동일 soul 디듑 — 같은 배치에 편성되지 않아 epoch 비중첩
# ───────────────────────────────────────────────────────────────────────────

@test "flow: parallel — 동일 soul 스텝 2개는 배치 디듑으로 비중첩 실행" {
  _mk_steps <<'JSON'
[
  {"id":"s1","soul":"dup_soul","task":"t1","deps":[]},
  {"id":"s2","soul":"dup_soul","task":"t2","deps":[]}
]
JSON
  run flow_create "dedup flow" "$TEST_PROJECT/steps.json"
  local flow_id="$output"

  # task 인자는 [플로우 컨텍스트] 프리픽스가 붙은 전체 프롬프트 — 원본 task 명은
  # 부분 매칭으로 추출한다 (리터럴 ${task} 파일명은 공백 포함 전체 프롬프트가 됨)
  agent_run() {
    local key
    case "$2" in
      *t1*) key=t1 ;;
      *t2*) key=t2 ;;
      *) key=unknown ;;
    esac
    date +%s > "$TEST_PROJECT/.start.${key}"
    sleep 1.1
    date +%s > "$TEST_PROJECT/.end.${key}"
    echo ok
    return 0
  }

  export GOLEM_FLOW_PARALLEL=2
  run flow_run "$flow_id"
  [ "$status" -eq 0 ]

  local end1 start2
  end1=$(cat "$TEST_PROJECT/.end.t1")
  start2=$(cat "$TEST_PROJECT/.start.t2")
  [ "$start2" -ge "$end1" ]
}

# ───────────────────────────────────────────────────────────────────────────
# 6. rank 게이트 — novice/junior soul은 배치 제외 + 직렬 꼬리, gate=0이면 해제
# ───────────────────────────────────────────────────────────────────────────

@test "flow: parallel — rank 게이트: novice는 배치와 비중첩, GOLEM_FLOW_PARALLEL_RANK_GATE=0이면 해제" {
  _mk_soul "novsoul" "novice"
  _mk_steps <<'JSON'
[
  {"id":"nov","soul":"novsoul","task":"nov task","deps":[]},
  {"id":"reg","soul":"regsoul","task":"reg task","deps":[]}
]
JSON
  run flow_create "rank gate flow" "$TEST_PROJECT/steps.json"
  local flow_id="$output"
  local state="${FLOW_DIR}/${flow_id}/state.json"

  export GOLEM_FLOW_PARALLEL=2
  run flow_run "$flow_id"
  [ "$status" -eq 0 ]
  [[ "$output" == *"병렬 배치 실행: reg (N=1)"* ]]
  [[ "$output" != *"병렬 배치 실행: nov"* ]]
  [[ "$output" != *"nov reg"* ]]
  grep -q '"id":"nov"[^}]*"status":"done"' "$state"
  grep -q '"id":"reg"[^}]*"status":"done"' "$state"

  # 게이트 해제 — nov도 같은 배치에 편성됨
  run flow_create "rank gate off" "$TEST_PROJECT/steps.json"
  local flow_id2="$output"
  export GOLEM_FLOW_PARALLEL_RANK_GATE=0
  run flow_run "$flow_id2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"병렬 배치 실행: nov reg (N=2)"* ]]
  unset GOLEM_FLOW_PARALLEL_RANK_GATE
}

# ───────────────────────────────────────────────────────────────────────────
# 7. approval 혼합 그룹 — approval 형제 waiting_approval, agent 형제 실행
# ───────────────────────────────────────────────────────────────────────────

@test "flow: parallel — approval 혼합 그룹: 승인 대기와 agent 실행 공존, rc 0" {
  _mk_steps <<'JSON'
[
  {"id":"gate","soul":"gsoul","task":"needs ok","deps":[],"approval":true},
  {"id":"work","soul":"wsoul","task":"work","deps":[]}
]
JSON
  run flow_create "approval mix" "$TEST_PROJECT/steps.json"
  local flow_id="$output"
  local state="${FLOW_DIR}/${flow_id}/state.json"

  export GOLEM_FLOW_PARALLEL=2
  run flow_run "$flow_id"
  [ "$status" -eq 0 ]
  grep -q '"id":"gate"[^}]*"status":"waiting_approval"' "$state"
  grep -q '"id":"work"[^}]*"status":"done"' "$state"
}

# ───────────────────────────────────────────────────────────────────────────
# 8. 마커 연속성 — 스텝 시작~완료 마커 사이 다른 스텝 마커 미개입
# ───────────────────────────────────────────────────────────────────────────

@test "flow: parallel — 마커 연속성: 스텝 시작~완료 구간에 다른 스텝 마커 없음" {
  _mk_steps <<'JSON'
[
  {"id":"m1","soul":"msoul1","task":"t1","deps":[]},
  {"id":"m2","soul":"msoul2","task":"t2","deps":[]},
  {"id":"m3","soul":"msoul3","task":"t3","deps":[]}
]
JSON
  run flow_create "marker continuity" "$TEST_PROJECT/steps.json"
  local flow_id="$output"

  export GOLEM_FLOW_PARALLEL=3
  run flow_run "$flow_id"
  [ "$status" -eq 0 ]

  local id other other_hit segment
  for id in m1 m2 m3; do
    segment=$(printf '%s\n' "$output" | awk -v id="$id" '
      $0 ~ "\\[FLOW\\]\\[STEP\\]\\[" id "\\]" { capture=1 }
      capture { print }
      capture && $0 ~ "\\[FLOW\\]\\[STEP\\]\\[" id "\\] 완료" { exit }
    ')
    other_hit=0
    for other in m1 m2 m3; do
      [ "$other" = "$id" ] && continue
      echo "$segment" | grep -q "\[FLOW\]\[STEP\]\[${other}\]" && other_hit=1
    done
    [ "$other_hit" -eq 0 ]
  done
}

# ───────────────────────────────────────────────────────────────────────────
# 9. 직렬 기본 회귀 — GOLEM_FLOW_PARALLEL 미설정 시 기존 직렬 경로 무변화
# 전체 회귀는 test_flow.bats 전체 그린 유지로 증명(제약: 본 파일만 신규 수정).
# ───────────────────────────────────────────────────────────────────────────

@test "flow: parallel — GOLEM_FLOW_PARALLEL 미설정 시 기존 직렬 경로(배치 마커 없음)" {
  _mk_steps <<'JSON'
[
  {"id":"r1","soul":"rsoul1","task":"t1","deps":[]},
  {"id":"r2","soul":"rsoul2","task":"t2","deps":[]}
]
JSON
  run flow_create "serial default" "$TEST_PROJECT/steps.json"
  local flow_id="$output"
  unset GOLEM_FLOW_PARALLEL
  run flow_run "$flow_id"
  [ "$status" -eq 0 ]
  [[ "$output" != *"병렬 배치 실행"* ]]
  grep -q '"id":"r1"[^}]*"status":"done"' "${FLOW_DIR}/${flow_id}/state.json"
  grep -q '"id":"r2"[^}]*"status":"done"' "${FLOW_DIR}/${flow_id}/state.json"
}
