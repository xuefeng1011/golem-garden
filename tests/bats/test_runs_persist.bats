#!/usr/bin/env bats
# test_runs_persist.bats — 런 트래젝토리 영속화 (Phase A, lib/agent-runner.sh)
#
# 커버리지 (docs/OBSERVABILITY_PLAN.md 가드레일):
#   G5: 시크릿 마스킹 (sk-/ghp_/KEY=)
#   G4: GOLEM_RUNS_KEEP 개수 롤링 (jsonl+meta 쌍 삭제)
#   G6: meta 가 spec/run-meta.schema.json 의 필수 키 전부 포함 (골든)
#   escape hatch: GOLEM_RUNS_DISABLE=1 → 보존 없이 제거(기존 동작)
#
# 실제 claude 호출 없음 — _agent_persist_run 을 픽스처 스트림으로 직접 호출.

load "test_helper"

_source_runner() {
  export GOLEM_ROOT
  export GOLEM_DIR="$TEST_PROJECT/.golem"
  export GOLEM_PROJECT="$TEST_PROJECT"
  # shellcheck source=/dev/null
  source "${GOLEM_ROOT}/lib/agent-runner.sh"
  export GOLEM_DIR="$TEST_PROJECT/.golem"
  # meta 가 재사용하는 파싱 결과 전역 — 픽스처 값
  _AR_DURATION_MS=1234
  _AR_TOKENS_IN=10
  _AR_TOKENS_OUT=20
  _AR_TOKENS_CACHE=30
}

# 픽스처 스트림 파일 생성 (tool_use 2종 + 시크릿 포함)
_make_stream() {
  local f="$TEST_PROJECT/stream.jsonl"
  cat > "$f" <<'EOF'
{"type":"system","subtype":"init","session_id":"s1"}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Read","input":{"path":"a.txt"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Read","input":{"key":"sk-abcdefghijklmnop1234"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t3","name":"Bash","input":{"cmd":"export ANTHROPIC_API_KEY=secret-value-here"}}]}}
{"type":"result","duration_ms":1234,"is_error":false,"usage":{"input_tokens":10,"output_tokens":20}}
EOF
  printf '%s' "$f"
}

_persist() {
  # _persist <run_id> [stream_file]
  local rid="$1"
  local sf="${2:-$(_make_stream)}"
  _agent_persist_run "$sf" "$rid" "11111111-2222-4333-8444-555555555555" "zen" "haiku" "success" "0.012" "2026-06-12T00:00:00Z"
}

@test "runs: persist — jsonl + meta 쌍 생성, 원본 stream 제거" {
  _source_runner
  local sf
  sf=$(_make_stream)
  _persist "run-aaa" "$sf"
  [ -f "$TEST_PROJECT/.golem/runs/run-aaa.jsonl" ]
  [ -f "$TEST_PROJECT/.golem/runs/run-aaa.meta.json" ]
  [ ! -f "$sf" ]
}

@test "runs: G5 마스킹 — sk-/ANTHROPIC_API_KEY 값이 보존본에 없음" {
  _source_runner
  _persist "run-mask"
  local dest="$TEST_PROJECT/.golem/runs/run-mask.jsonl"
  run grep -c 'sk-abcdefghijklmnop1234' "$dest"
  [ "$output" = "0" ]
  run grep -c 'secret-value-here' "$dest"
  [ "$output" = "0" ]
  grep -q '\*\*\*MASKED\*\*\*' "$dest"
}

@test "runs: meta — tool_counts 근사 카운트 (Read 2, Bash 1)" {
  _source_runner
  _persist "run-tools"
  local meta="$TEST_PROJECT/.golem/runs/run-tools.meta.json"
  grep -q '"Read":2' "$meta"
  grep -q '"Bash":1' "$meta"
}

@test "runs: G6 골든 — meta 가 spec/run-meta.schema.json 필수 키 전부 포함" {
  _source_runner
  _persist "run-schema"
  local meta="$TEST_PROJECT/.golem/runs/run-schema.meta.json"
  # required 배열의 키 목록을 스키마에서 추출해 각각 meta 에 존재하는지 검증
  local keys k
  keys=$(grep -o '"[a-z_]*"' "${GOLEM_ROOT}/spec/run-meta.schema.json" \
    | sed -n '/"required"/,$p' | grep -v required | tr -d '"')
  # 단순화: required 13키를 직접 나열 (스키마 변경 시 이 테스트도 갱신)
  for k in run_id session_id soul model source ts_start duration_ms \
           tokens_in tokens_out tokens_cache cost_usd result tool_counts; do
    grep -q "\"$k\"" "$meta" || { echo "missing key: $k" >&2; return 1; }
  done
  grep -q '"source":"bash"' "$meta"
}

@test "runs: G4 롤링 — KEEP=3 에서 4번째 persist 시 최고령 쌍 삭제" {
  _source_runner
  export GOLEM_RUNS_KEEP=3
  local i
  for i in 1 2 3 4; do
    _persist "run-gc-$i"
    sleep 1  # mtime 순서 보장 (Windows 1s 해상도)
  done
  [ ! -f "$TEST_PROJECT/.golem/runs/run-gc-1.jsonl" ]
  [ ! -f "$TEST_PROJECT/.golem/runs/run-gc-1.meta.json" ]
  [ -f "$TEST_PROJECT/.golem/runs/run-gc-4.jsonl" ]
  [ -f "$TEST_PROJECT/.golem/runs/run-gc-2.jsonl" ]
}

@test "runs: GOLEM_RUNS_DISABLE=1 — 보존 없이 stream 제거 (기존 동작)" {
  _source_runner
  export GOLEM_RUNS_DISABLE=1
  local sf
  sf=$(_make_stream)
  _persist "run-off" "$sf"
  [ ! -f "$sf" ]
  [ ! -f "$TEST_PROJECT/.golem/runs/run-off.jsonl" ]
}

@test "runs: persist 는 항상 exit 0 (soft-fail — 쓰기 불가여도 런을 죽이지 않음)" {
  _source_runner
  # 존재하지 않는 stream 파일 → 그냥 0
  run _agent_persist_run "/no/such/file" "run-x" "s" "zen" "haiku" "success" "0" "t"
  [ "$status" -eq 0 ]
}
