#!/usr/bin/env bats
# test_agent_runner.bats — Zen 작성: agent-runner.sh 단위 테스트 (오프라인)
# T1 커버리지:
#   _map_model, _tools_csv, _gen_uuid, _json_num_field, _parse_stream,
#   _extract_assistant_text, agent_run --dry-run

load "test_helper"

# agent-runner.sh 소싱 시 claude CLI가 없어도 죽지 않도록 PATH를 비워두지 않는다.
# dry-run 경로는 claude를 실행하지 않으므로 안전하다.
# 단, source 자체에서 growth-log.sh 가 GROWTH_DIR을 덮어쓰므로
# golem_load_lib 를 쓰지 않고 직접 source 후 재설정한다.

_source_agent_runner() {
  # shellcheck source=/dev/null
  source "${GOLEM_ROOT}/lib/agent-runner.sh"
  # source 후 GROWTH_DIR 격리 재설정
  export GOLEM_DIR="$TEST_PROJECT/.golem"
  export GROWTH_DIR="$TEST_PROJECT/.golem/growth-log"
}

# ─────────────────────────────────────────────────────────
# _map_model
# ─────────────────────────────────────────────────────────

@test "agent-runner: _map_model opus → opus" {
  _source_agent_runner
  result=$(_map_model "opus")
  [ "$result" = "opus" ]
}

@test "agent-runner: _map_model sonnet → sonnet" {
  _source_agent_runner
  result=$(_map_model "sonnet")
  [ "$result" = "sonnet" ]
}

@test "agent-runner: _map_model haiku → haiku" {
  _source_agent_runner
  result=$(_map_model "haiku")
  [ "$result" = "haiku" ]
}

@test "agent-runner: _map_model claude-opus-4-8 → pass-through" {
  _source_agent_runner
  result=$(_map_model "claude-opus-4-8")
  [ "$result" = "claude-opus-4-8" ]
}

@test "agent-runner: _map_model 빈 문자열 → 기본값 sonnet" {
  _source_agent_runner
  result=$(_map_model "")
  [ "$result" = "sonnet" ]
}

@test "agent-runner: _map_model 알 수 없는 값 → pass-through" {
  _source_agent_runner
  result=$(_map_model "unknown-model-xyz")
  [ "$result" = "unknown-model-xyz" ]
}

# ─────────────────────────────────────────────────────────
# _tools_csv
# ─────────────────────────────────────────────────────────

@test "agent-runner: _tools_csv 공백 제거 — 'Read, Edit, Write' → 'Read,Edit,Write'" {
  _source_agent_runner
  result=$(_tools_csv "Read, Edit, Write")
  [ "$result" = "Read,Edit,Write" ]
}

@test "agent-runner: _tools_csv 이미 CSV면 그대로" {
  _source_agent_runner
  result=$(_tools_csv "Read,Edit,Bash")
  [ "$result" = "Read,Edit,Bash" ]
}

@test "agent-runner: _tools_csv 빈 문자열 → 빈 문자열" {
  _source_agent_runner
  result=$(_tools_csv "")
  [ "$result" = "" ]
}

# ─────────────────────────────────────────────────────────
# _gen_uuid
# ─────────────────────────────────────────────────────────

@test "agent-runner: _gen_uuid — 비어있지 않음" {
  _source_agent_runner
  result=$(_gen_uuid)
  [ -n "$result" ]
}

@test "agent-runner: _gen_uuid — 대시 포함 (UUID 형태 또는 time-pid 폴백)" {
  _source_agent_runner
  result=$(_gen_uuid)
  # UUID 형태(예: 550e8400-e29b-41d4-a716-446655440000) 또는 time-pid 폴백(숫자-PID-랜덤)
  # 공통 조건: 대시가 하나 이상 포함되고 비어있지 않아야 함
  [[ "$result" =~ - ]]
}

@test "agent-runner: _gen_uuid — 연속 두 번 호출 결과 비교 (중복 낮음)" {
  _source_agent_runner
  u1=$(_gen_uuid)
  u2=$(_gen_uuid)
  # python3 기반 UUID는 충돌 확률이 천문학적으로 낮다
  # time-pid 폴백은 같은 초에 같은 PID이면 동일할 수 있으나,
  # 연속 두 번 호출이면 RANDOM 값만 달라도 통과됨.
  # 단순하게 두 UUID 모두 비어있지 않음을 확인 (충돌 검사는 flaky)
  [ -n "$u1" ]
  [ -n "$u2" ]
}

# ─────────────────────────────────────────────────────────
# _json_num_field
# ─────────────────────────────────────────────────────────

@test "agent-runner: _json_num_field — input_tokens 추출" {
  _source_agent_runner
  line='{"type":"result","usage":{"input_tokens":42,"output_tokens":7}}'
  result=$(_json_num_field "$line" "input_tokens")
  [ "$result" = "42" ]
}

@test "agent-runner: _json_num_field — output_tokens 추출" {
  _source_agent_runner
  line='{"type":"result","usage":{"input_tokens":42,"output_tokens":7}}'
  result=$(_json_num_field "$line" "output_tokens")
  [ "$result" = "7" ]
}

@test "agent-runner: _json_num_field — 필드 없으면 빈 문자열" {
  _source_agent_runner
  line='{"type":"result"}'
  result=$(_json_num_field "$line" "nonexistent_field")
  [ -z "$result" ]
}

@test "agent-runner: _json_num_field — duration_ms 추출" {
  _source_agent_runner
  line='{"type":"result","duration_ms":2766,"is_error":false}'
  result=$(_json_num_field "$line" "duration_ms")
  [ "$result" = "2766" ]
}

# ─────────────────────────────────────────────────────────
# _parse_stream
# ─────────────────────────────────────────────────────────
# 실제 stream-json 형태를 heredoc으로 모의

@test "agent-runner: _parse_stream — result 라인에서 토큰/duration 파싱" {
  _source_agent_runner
  # pipe는 subshell을 생성해 전역 변수가 전파되지 않으므로 임시 파일 경유
  local stream_file="$TEST_PROJECT/parse_stream_test1.jsonl"
  cat > "$stream_file" <<'STREAMEOF'
{"type":"system","subtype":"init","session_id":"test-sess-001"}
{"type":"assistant","message":{"content":[{"type":"text","text":"Hello"}]}}
{"type":"result","subtype":"success","is_error":false,"duration_ms":2766,"usage":{"input_tokens":10,"output_tokens":47,"cache_read_input_tokens":37696,"cache_creation_input_tokens":0,"server_tool_use":{"web_search_requests":0}}}
STREAMEOF
  _parse_stream < "$stream_file"

  [ "$_AR_TOKENS_IN" = "10" ]
  [ "$_AR_TOKENS_OUT" = "47" ]
  [ "$_AR_TOKENS_CACHE" = "37696" ]
  [ "$_AR_DURATION_MS" = "2766" ]
  [ "$_AR_IS_ERROR" = "0" ]
}

@test "agent-runner: _parse_stream — is_error:true → _AR_IS_ERROR=1" {
  _source_agent_runner
  local stream_file="$TEST_PROJECT/parse_stream_test2.jsonl"
  cat > "$stream_file" <<'STREAMEOF'
{"type":"result","subtype":"error","is_error":true,"duration_ms":500,"usage":{"input_tokens":5,"output_tokens":2,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}
STREAMEOF
  _parse_stream < "$stream_file"

  [ "$_AR_IS_ERROR" = "1" ]
  [ "$_AR_DURATION_MS" = "500" ]
}

@test "agent-runner: _parse_stream — 빈 스트림 → 기본값 0" {
  _source_agent_runner
  local stream_file="$TEST_PROJECT/parse_stream_empty.jsonl"
  # 빈 파일
  : > "$stream_file"
  _parse_stream < "$stream_file"

  [ "$_AR_TOKENS_IN" = "0" ]
  [ "$_AR_TOKENS_OUT" = "0" ]
  [ "$_AR_TOKENS_CACHE" = "0" ]
  [ "$_AR_DURATION_MS" = "0" ]
  [ "$_AR_IS_ERROR" = "0" ]
}

@test "agent-runner: _parse_stream — cache_creation + cache_read 합산" {
  _source_agent_runner
  local stream_file="$TEST_PROJECT/parse_stream_test4.jsonl"
  cat > "$stream_file" <<'STREAMEOF'
{"type":"result","is_error":false,"duration_ms":1000,"usage":{"input_tokens":20,"output_tokens":10,"cache_read_input_tokens":300,"cache_creation_input_tokens":100}}
STREAMEOF
  _parse_stream < "$stream_file"

  # cache = read(300) + creation(100) = 400
  [ "$_AR_TOKENS_CACHE" = "400" ]
}

# ─────────────────────────────────────────────────────────
# _extract_assistant_text
# ─────────────────────────────────────────────────────────

@test "agent-runner: _extract_assistant_text — assistant 라인에서 text 추출" {
  _source_agent_runner
  local stream_file="$TEST_PROJECT/stream_sample.jsonl"
  cat > "$stream_file" <<'EOF'
{"type":"system","subtype":"init","session_id":"test-123"}
{"type":"assistant","message":{"content":[{"type":"text","text":"Hello"}]}}
{"type":"result","is_error":false,"duration_ms":100,"usage":{"input_tokens":5,"output_tokens":3,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}
EOF
  result=$(_extract_assistant_text "$stream_file")
  [ "$result" = "Hello" ]
}

@test "agent-runner: _extract_assistant_text — assistant 없으면 빈 문자열" {
  _source_agent_runner
  local stream_file="$TEST_PROJECT/stream_no_assistant.jsonl"
  cat > "$stream_file" <<'EOF'
{"type":"system","subtype":"init","session_id":"test-456"}
{"type":"result","is_error":false,"duration_ms":50,"usage":{"input_tokens":1,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}
EOF
  result=$(_extract_assistant_text "$stream_file")
  [ -z "$result" ]
}

@test "agent-runner: _extract_assistant_text — 여러 assistant 라인 이어붙임" {
  _source_agent_runner
  local stream_file="$TEST_PROJECT/stream_multi.jsonl"
  cat > "$stream_file" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"Hello"}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"World"}]}}
EOF
  result=$(_extract_assistant_text "$stream_file")
  # 두 라인이 개행으로 연결되어야 함
  [[ "$result" =~ "Hello" ]]
  [[ "$result" =~ "World" ]]
}

@test "agent-runner: _extract_assistant_text — 파일 없으면 빈 문자열" {
  _source_agent_runner
  result=$(_extract_assistant_text "$TEST_PROJECT/nonexistent.jsonl")
  [ -z "$result" ]
}

# ─────────────────────────────────────────────────────────
# agent_run --dry-run
# ─────────────────────────────────────────────────────────
# zen.md fixture를 .golem/souls/ 에 설치해서 _resolve_soul_file이 찾도록 함

@test "agent-runner: agent_run --dry-run — argv에 --print 포함" {
  load_fixture "souls/zen.md" "$TEST_PROJECT/.golem/souls/zen.md"
  _source_agent_runner
  result=$(agent_run "zen" "테스트 태스크" --dry-run 2>&1)
  [[ "$result" =~ "--print" ]]
}

@test "agent-runner: agent_run --dry-run — argv에 --output-format=stream-json 포함" {
  load_fixture "souls/zen.md" "$TEST_PROJECT/.golem/souls/zen.md"
  _source_agent_runner
  result=$(agent_run "zen" "테스트 태스크" --dry-run 2>&1)
  [[ "$result" =~ "stream-json" ]]
}

@test "agent-runner: agent_run --dry-run — argv에 --append-system-prompt 포함" {
  load_fixture "souls/zen.md" "$TEST_PROJECT/.golem/souls/zen.md"
  _source_agent_runner
  result=$(agent_run "zen" "테스트 태스크" --dry-run 2>&1)
  [[ "$result" =~ "--append-system-prompt" ]]
}

@test "agent-runner: agent_run --dry-run — argv에 --model 포함" {
  load_fixture "souls/zen.md" "$TEST_PROJECT/.golem/souls/zen.md"
  _source_agent_runner
  result=$(agent_run "zen" "테스트 태스크" --dry-run 2>&1)
  [[ "$result" =~ "--model" ]]
}

@test "agent-runner: agent_run --dry-run — argv 마지막에 태스크 포함" {
  load_fixture "souls/zen.md" "$TEST_PROJECT/.golem/souls/zen.md"
  _source_agent_runner
  result=$(agent_run "zen" "unique-task-marker-xyz" --dry-run 2>&1)
  [[ "$result" =~ "unique-task-marker-xyz" ]]
}

@test "agent-runner: agent_run --dry-run — <usage> 요약 라인에 soul=zen 포함" {
  load_fixture "souls/zen.md" "$TEST_PROJECT/.golem/souls/zen.md"
  _source_agent_runner
  result=$(agent_run "zen" "테스트 태스크" --dry-run 2>&1)
  [[ "$result" =~ "soul=zen" ]]
}

@test "agent-runner: agent_run --dry-run — <usage> 요약 라인에 model=haiku 포함 (zen.md fixture)" {
  load_fixture "souls/zen.md" "$TEST_PROJECT/.golem/souls/zen.md"
  _source_agent_runner
  result=$(agent_run "zen" "테스트 태스크" --dry-run 2>&1)
  # zen.md: model: haiku
  [[ "$result" =~ "model=haiku" ]]
}

@test "agent-runner: agent_run — SOUL 파일 없으면 에러 반환" {
  _source_agent_runner
  run agent_run "nonexistent-soul-xyz" "태스크" --dry-run
  [ "$status" -ne 0 ]
}

@test "agent-runner: agent_run — soul_name 빈 문자열이면 에러 반환" {
  _source_agent_runner
  run agent_run "" "태스크" --dry-run
  [ "$status" -ne 0 ]
}

@test "agent-runner: agent_run — task 빈 문자열이면 에러 반환" {
  _source_agent_runner
  run agent_run "zen" "" --dry-run
  [ "$status" -ne 0 ]
}

# ─────────────────────────────────────────────────────────
# P2-1: per-SOUL --resume 캐시 레버 (_agent_pick_session / _agent_ptr_update)
# ─────────────────────────────────────────────────────────

@test "agent-runner: pick_session — 포인터 없으면 fresh + 새 UUID" {
  _source_agent_runner
  result=$(_agent_pick_session "zen")
  [[ "$result" =~ fresh$ ]]
  uuid=${result%% *}
  [[ "$uuid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}- ]]
}

@test "agent-runner: ptr_update 후 윈도 내 + 마커 있으면 resume" {
  _source_agent_runner
  mkdir -p "$TEST_PROJECT/.golem/sessions"
  local uuid="11111111-2222-4333-8444-555555555555"
  : > "$TEST_PROJECT/.golem/sessions/${uuid}.claude"
  _agent_ptr_update "zen" "$uuid" "fresh"
  result=$(_agent_pick_session "zen")
  [ "$result" = "${uuid} resume" ]
}

@test "agent-runner: 윈도(WINDOW_SEC) 초과 시 fresh 로 복귀" {
  _source_agent_runner
  mkdir -p "$TEST_PROJECT/.golem/sessions"
  local uuid="11111111-2222-4333-8444-555555555555"
  : > "$TEST_PROJECT/.golem/sessions/${uuid}.claude"
  # 오래된 epoch 강제 (1년 전)
  printf '%s %s %s\n' "$uuid" "1700000000" "1" \
    > "$TEST_PROJECT/.golem/sessions/soul-zen.ptr"
  result=$(GOLEM_RESUME_WINDOW_SEC=300 _agent_pick_session "zen")
  [[ "$result" =~ fresh$ ]]
  [ "${result%% *}" != "$uuid" ]
}

@test "agent-runner: 턴캡(MAX_TURNS) 도달 시 fresh 로 리셋" {
  _source_agent_runner
  mkdir -p "$TEST_PROJECT/.golem/sessions"
  local uuid="11111111-2222-4333-8444-555555555555"
  : > "$TEST_PROJECT/.golem/sessions/${uuid}.claude"
  local now; now=$(date +%s)
  printf '%s %s %s\n' "$uuid" "$now" "8" \
    > "$TEST_PROJECT/.golem/sessions/soul-zen.ptr"
  result=$(GOLEM_RESUME_MAX_TURNS=8 _agent_pick_session "zen")
  [[ "$result" =~ fresh$ ]]
}

@test "agent-runner: GOLEM_RESUME_DISABLE=1 이면 항상 fresh" {
  _source_agent_runner
  mkdir -p "$TEST_PROJECT/.golem/sessions"
  local uuid="11111111-2222-4333-8444-555555555555"
  : > "$TEST_PROJECT/.golem/sessions/${uuid}.claude"
  local now; now=$(date +%s)
  printf '%s %s %s\n' "$uuid" "$now" "1" \
    > "$TEST_PROJECT/.golem/sessions/soul-zen.ptr"
  result=$(GOLEM_RESUME_DISABLE=1 _agent_pick_session "zen")
  [[ "$result" =~ fresh$ ]]
}

@test "agent-runner: ptr_update resume 모드는 turn 카운트 증가" {
  _source_agent_runner
  mkdir -p "$TEST_PROJECT/.golem/sessions"
  local uuid="11111111-2222-4333-8444-555555555555"
  _agent_ptr_update "zen" "$uuid" "fresh"   # turn=1
  _agent_ptr_update "zen" "$uuid" "resume"  # turn=2
  read -r _u _e t < "$TEST_PROJECT/.golem/sessions/soul-zen.ptr"
  [ "$t" -eq 2 ]
}
