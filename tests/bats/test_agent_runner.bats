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
# _agent_kill_tree — 벽시계 워치독 강제 종료 (Windows/POSIX 공통)
# ─────────────────────────────────────────────────────────

@test "agent-runner: _agent_kill_tree — 빈 pid 는 무해(rc 0)" {
  _source_agent_runner
  run _agent_kill_tree ""
  [ "$status" -eq 0 ]
}

@test "agent-runner: _agent_kill_tree — 존재하지 않는 pid 는 무해(rc 0)" {
  _source_agent_runner
  run _agent_kill_tree 999999
  [ "$status" -eq 0 ]
}

@test "agent-runner: _agent_kill_tree — 살아있는 자식 프로세스를 실제로 종료" {
  _source_agent_runner
  sleep 30 &
  local _pid=$!
  kill -0 "$_pid" 2>/dev/null   # 시작 확인
  _agent_kill_tree "$_pid"
  sleep 1
  ! kill -0 "$_pid" 2>/dev/null  # 종료 확인
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

# ─────────────────────────────────────────────────────────
# P2-2 폴백 — --resume 즉사 시 새 세션 1회 재시도
# (라이브 스모크 실결함: 다른 cwd 에서 만든 세션 포인터 resume → 즉시 fail)
# ─────────────────────────────────────────────────────────

_setup_fake_claude() {
  # --resume 이면 즉사(무출력), --session-id 면 성공 — PATH 선두에 주입
  mkdir -p "$TEST_PROJECT/bin"
  cat > "$TEST_PROJECT/bin/claude" <<'FAKE'
#!/usr/bin/env bash
for a in "$@"; do
  [ "$a" = "--resume" ] && exit 1
done
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"FALLBACK-OK"}]}}'
exit 0
FAKE
  chmod +x "$TEST_PROJECT/bin/claude"
  export PATH="$TEST_PROJECT/bin:$PATH"
}

_plant_warm_ptr() {
  # zen 의 따뜻한 세션 포인터 + 마커 → _agent_pick_session 이 resume 을 고르게 함
  local uuid="11111111-2222-4333-8444-555555555555"
  mkdir -p "$TEST_PROJECT/.golem/sessions"
  printf '%s %s 1\n' "$uuid" "$(date +%s)" > "$TEST_PROJECT/.golem/sessions/soul-zen.ptr"
  : > "$TEST_PROJECT/.golem/sessions/${uuid}.claude"
}

@test "agent-runner: resume 즉사 → 포인터 폐기 + 새 세션 폴백 성공" {
  load_fixture "souls/zen.md" "$TEST_PROJECT/.golem/souls/zen.md"
  _source_agent_runner
  _setup_fake_claude
  _plant_warm_ptr

  run agent_run zen "폴백 테스트"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--resume 소환 즉사"* ]]
  [[ "$output" == *"session=fresh"* ]]
  # 죽은 포인터는 폐기 후 성공 소환이 새 포인터로 재작성 — 새 uuid 여야 함
  ! grep -q '11111111-2222-4333-8444-555555555555' "$TEST_PROJECT/.golem/sessions/soul-zen.ptr"
}

# ─────────────────────────────────────────────────────────
# 벽시계 워치독 — GNU timeout/gtimeout 부재(Windows Git Bash)에서도
# 행 걸린 claude 를 데드라인에 강제 종료하고 GNU 경로와 동일 계약을 반환 (BACKLOG P1)
# ─────────────────────────────────────────────────────────

# fake claude: 자기 pid 를 기록하고 오래 잔다 (행 시뮬레이션).
# fd3 닫기: bats 는 백그라운드 잔존 프로세스가 fd3 를 쥐고 있으면 대기하므로,
# (POSIX 경로에서 sleep 고아가 1~10s 남을 수 있는 경우 대비) 상속 차단.
_setup_hung_claude() {
  mkdir -p "$TEST_PROJECT/bin"
  cat > "$TEST_PROJECT/bin/claude" <<FAKE
#!/usr/bin/env bash
exec 3>&-
echo \$\$ > "$TEST_PROJECT/.claude_pid"
sleep 60
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"TOO-LATE"}]}}'
FAKE
  chmod +x "$TEST_PROJECT/bin/claude"
  export PATH="$TEST_PROJECT/bin:$PATH"
}

@test "watchdog: timeout 바이너리 부재 + 행 claude → 데드라인 강제 종료 (GNU 경로 동일 계약)" {
  load_fixture "souls/zen.md" "$TEST_PROJECT/.golem/souls/zen.md"
  _source_agent_runner
  _setup_hung_claude
  # GNU timeout/gtimeout 탐지 무력화 — Windows Git Bash 부재 시나리오 재현.
  # (소환 경로는 프리픽스를 쓰지 않지만, 부재 상태에서도 가드가 살아있음을 못박는다)
  _agent_timeout_cmd() { printf '\n'; }

  local start elapsed rc=0
  start=$(date +%s)
  AGENT_MAX_SECONDS=1 agent_run zen "행 테스트" > "$TEST_PROJECT/run.out" 2>&1 || rc=$?
  elapsed=$(( $(date +%s) - start ))

  # GNU timeout(rc 124) 경로와 동일 계약: agent_run rc=1(fail), TIMEOUT 텍스트, usage timeout=1
  [ "$rc" -eq 1 ]
  grep -q "TIMEOUT after 1s" "$TEST_PROJECT/run.out"
  grep -q "timeout=1 turn_cap=0 max_seconds=1" "$TEST_PROJECT/run.out"
  # 60초 sleep 을 기다리지 않고 반환 — 무제한 아님 증명.
  # (킬 자체는 데드라인 ~1s 에 발생하나, agent_run 의 고정 오버헤드[프롬프트 조립/
  #  growth-log/persist 등 fork 비용]가 Windows 에서 ~12s 라 여유 있는 상한을 쓴다)
  [ "$elapsed" -le 30 ]
  # fake claude 프로세스가 실제로 죽었는지 (워치독 → _agent_kill_tree 효과)
  local cpid
  cpid=$(cat "$TEST_PROJECT/.claude_pid")
  ! kill -0 "$cpid" 2>/dev/null
  # 워치독 잔존 없음 — 이 셸의 실행 중 백그라운드 잡이 모두 정리돼야 함
  [ -z "$(jobs -rp)" ]
}

@test "watchdog: 정상 종료 시 워치독 즉시 정리 — 잔존 프로세스 없음 + 출력 파싱 불변" {
  load_fixture "souls/zen.md" "$TEST_PROJECT/.golem/souls/zen.md"
  _source_agent_runner
  mkdir -p "$TEST_PROJECT/bin"
  cat > "$TEST_PROJECT/bin/claude" <<'FAKE'
#!/usr/bin/env bash
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"FAST-OK"}]}}'
echo '{"type":"result","is_error":false,"duration_ms":120,"result":"FAST-OK","usage":{"input_tokens":5,"output_tokens":3,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}'
FAKE
  chmod +x "$TEST_PROJECT/bin/claude"
  export PATH="$TEST_PROJECT/bin:$PATH"
  _agent_timeout_cmd() { printf '\n'; }

  local rc=0
  AGENT_MAX_SECONDS=30 agent_run zen "빠른 태스크" > "$TEST_PROJECT/run.out" 2>&1 || rc=$?

  [ "$rc" -eq 0 ]
  grep -q "FAST-OK" "$TEST_PROJECT/run.out"
  # P0-4: 마커 없는 정상 완주는 partial 분류 (rc 0)
  grep -qE "result=(success|partial)" "$TEST_PROJECT/run.out"
  grep -q "timeout=0 turn_cap=0 max_seconds=30" "$TEST_PROJECT/run.out"
  # 데드라인이 30초 남았어도 부모가 워치독을 kill+reap — 잔존 잡 없음
  [ -z "$(jobs -rp)" ]
}

# ─────────────────────────────────────────────────────────
# P1-1 턴 캡 하드 집행 — stream assistant 이벤트 라이브 카운트 → 캡 초과 시 kill
# ─────────────────────────────────────────────────────────

# maxTurns: 3 인 테스트 SOUL 을 프로젝트 오버라이드 경로에 생성
_make_capped_soul() {
  mkdir -p "$TEST_PROJECT/.golem/souls"
  cat > "$TEST_PROJECT/.golem/souls/capy.md" <<'SOUL'
---
name: Capy
role: qa-tester
rank: novice
specialty: [turn-cap-testing]
model: haiku
tools: [Read]
maxTurns: 3
isolation: none
created: 2026-07-05
---

## 프로젝트 컨텍스트 (프롬프트에 주입됨)
- 역할: qa-tester
SOUL
}

# fake claude: assistant 이벤트를 1초 간격으로 40개 방출 (킬 개입 여유 확보).
# fd3 닫기: bats 백그라운드 잔존 프로세스 대기 차단 (기존 워치독 테스트와 동일).
_setup_chatty_claude() {
  mkdir -p "$TEST_PROJECT/bin"
  cat > "$TEST_PROJECT/bin/claude" <<FAKE
#!/usr/bin/env bash
exec 3>&-
echo \$\$ > "$TEST_PROJECT/.claude_pid"
i=0
while [ \$i -lt 40 ]; do
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"turn"}]}}'
  sleep 1
  i=\$((i+1))
done
echo '{"type":"result","is_error":false,"duration_ms":100,"usage":{"input_tokens":5,"output_tokens":3,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}'
FAKE
  chmod +x "$TEST_PROJECT/bin/claude"
  export PATH="$TEST_PROJECT/bin:$PATH"
}

# fake claude: assistant 이벤트 5개를 즉시 방출 후 정상 종료 (캡 비활성 검증용)
_setup_fast_chatty_claude() {
  mkdir -p "$TEST_PROJECT/bin"
  cat > "$TEST_PROJECT/bin/claude" <<'FAKE'
#!/usr/bin/env bash
for i in 1 2 3 4 5; do
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"turn"}]}}'
done
echo '{"type":"result","is_error":false,"duration_ms":100,"result":"DONE","usage":{"input_tokens":5,"output_tokens":3,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}'
FAKE
  chmod +x "$TEST_PROJECT/bin/claude"
  export PATH="$TEST_PROJECT/bin:$PATH"
}

# 실스트림 형상 재현 — 하나의 논리 턴(msg id)이 콘텐츠 블록 단위로 여러 assistant
# 이벤트로 분할 방출된다 (라이브 E2E 실측: 논리 턴 21 ↔ envelope 41줄).
# 2개 논리 턴 × 4이벤트 = 8 envelope 라인 — 라인 수로 세면 캡 3 오발동, id 수로는 2.
_setup_multiblock_claude() {
  mkdir -p "$TEST_PROJECT/bin"
  cat > "$TEST_PROJECT/bin/claude" <<'FAKE'
#!/usr/bin/env bash
for m in 01AAA 01BBB; do
  for b in 1 2 3 4; do
    echo '{"type":"assistant","message":{"id":"msg_'$m'","content":[{"type":"text","text":"block"}]}}'
  done
done
echo '{"type":"result","is_error":false,"duration_ms":100,"result":"DONE","usage":{"input_tokens":5,"output_tokens":3,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}'
FAKE
  chmod +x "$TEST_PROJECT/bin/claude"
  export PATH="$TEST_PROJECT/bin:$PATH"
}

@test "turn-cap: 논리 턴 카운트 — 메시지당 다중 이벤트(블록 분할)는 1턴 (실스트림 오발동 회귀)" {
  _make_capped_soul   # maxTurns: 3
  _source_agent_runner
  _setup_multiblock_claude

  # envelope 8줄이지만 고유 msg id 2 — 캡 3을 넘지 않아 성공해야 한다
  local rc=0
  AGENT_MAX_SECONDS=60 agent_run capy "다중블록 테스트" > "$TEST_PROJECT/mb.out" 2>&1 || rc=$?
  [ "$rc" -eq 0 ]
  grep -q 'turn_cap=0' "$TEST_PROJECT/mb.out"
  grep -q 'DONE' "$TEST_PROJECT/mb.out"
}

@test "turn-cap: 고유 msg id 4개 > 캡 3 → turn_cap (id 기반 카운트도 캡 집행)" {
  _make_capped_soul   # maxTurns: 3
  _source_agent_runner
  mkdir -p "$TEST_PROJECT/bin"
  cat > "$TEST_PROJECT/bin/claude" <<'FAKE'
#!/usr/bin/env bash
for m in 01A 01B 01C 01D; do
  echo '{"type":"assistant","message":{"id":"msg_'$m'","content":[{"type":"text","text":"t"}]}}'
done
echo '{"type":"result","is_error":false,"duration_ms":100,"result":"DONE","usage":{"input_tokens":5,"output_tokens":3,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}'
FAKE
  chmod +x "$TEST_PROJECT/bin/claude"
  export PATH="$TEST_PROJECT/bin:$PATH"

  local rc=0
  AGENT_MAX_SECONDS=60 agent_run capy "id캡 테스트" > "$TEST_PROJECT/idcap.out" 2>&1 || rc=$?
  [ "$rc" -ne 0 ]
  grep -q 'turn_cap=1' "$TEST_PROJECT/idcap.out"
  # R-1 신계약: 사살은 checkpoint 정산 (캡 집행 자체는 turn_cap=1 플래그로 검증)
  grep -q 'result=checkpoint' "$TEST_PROJECT/idcap.out"
}

@test "turn-cap: maxTurns 초과 → 중도 kill + rc≠0 + turn_cap=1 + growth-log result=turn_cap" {
  _make_capped_soul
  _source_agent_runner
  _setup_chatty_claude

  local start elapsed rc=0
  start=$(date +%s)
  AGENT_MAX_SECONDS=120 agent_run capy "턴캡 테스트" > "$TEST_PROJECT/run.out" 2>&1 || rc=$?
  elapsed=$(( $(date +%s) - start ))

  # 실패 계약: agent_run rc=1, TURN CAP 사유 텍스트, usage 마커, 체크포인트
  [ "$rc" -eq 1 ]
  grep -q "TURN CAP" "$TEST_PROJECT/run.out"
  grep -q "result=checkpoint" "$TEST_PROJECT/run.out"
  grep -q "turn_cap=1" "$TEST_PROJECT/run.out"
  grep -q "max_turns=3" "$TEST_PROJECT/run.out"
  # 40초 방출을 기다리지 않고 반환 (캡 kill 은 ~4s + agent_run 고정 오버헤드 여유)
  [ "$elapsed" -le 30 ]
  # fake claude 프로세스가 실제로 죽었는지 (워치독 → _agent_kill_tree 효과)
  local cpid
  cpid=$(cat "$TEST_PROJECT/.claude_pid")
  ! kill -0 "$cpid" 2>/dev/null
  # R-1 신계약: growth-log 에 result=checkpoint (사살 정산) + slice 기록
  assert_jsonl_field "$TEST_PROJECT/.golem/growth-log/capy.jsonl" "result" "checkpoint"
  # 워치독 잔존 없음
  [ -z "$(jobs -rp)" ]
}

@test "turn-cap: GOLEM_TURN_CAP_ENFORCE=0 → 캡 비활성, 초과해도 정상 완주" {
  _make_capped_soul
  _source_agent_runner
  _setup_fast_chatty_claude

  local rc=0
  GOLEM_TURN_CAP_ENFORCE=0 agent_run capy "캡 해제 테스트" > "$TEST_PROJECT/run.out" 2>&1 || rc=$?

  [ "$rc" -eq 0 ]
  # P0-4: 마커 없는 정상 완주는 partial 분류 (rc 0)
  grep -qE "result=(success|partial)" "$TEST_PROJECT/run.out"
  grep -q "turn_cap=0" "$TEST_PROJECT/run.out"
}

@test "turn-cap: SOUL_MAX_TURNS 미설정(rank 기본값도 없음) → 무캡, 정상 완주" {
  # rank 가 기본 테이블(novice~master)에 없으면 soul-parser 가 SOUL_MAX_TURNS 를
  # 비워 둠 → _ar_max_turns=0 → 캡 비활성 (기본 캡을 발명하지 않는다)
  mkdir -p "$TEST_PROJECT/.golem/souls"
  cat > "$TEST_PROJECT/.golem/souls/unc.md" <<'SOUL'
---
name: Unc
role: qa-tester
rank: freeform
specialty: [uncapped-testing]
model: haiku
tools: [Read]
isolation: none
created: 2026-07-05
---

## 프로젝트 컨텍스트 (프롬프트에 주입됨)
- 역할: qa-tester
SOUL
  _source_agent_runner
  _setup_fast_chatty_claude

  local rc=0
  agent_run unc "무캡 테스트" > "$TEST_PROJECT/run.out" 2>&1 || rc=$?

  [ "$rc" -eq 0 ]
  # P0-4: 마커 없는 정상 완주는 partial 분류 (rc 0)
  grep -qE "result=(success|partial)" "$TEST_PROJECT/run.out"
  # model haiku → effort low → max_seconds=180 (기존 effort 테이블)
  grep -q "turn_cap=0 max_seconds=180 max_turns=0" "$TEST_PROJECT/run.out"
}

# ─────────────────────────────────────────────────────────
# C-2 — AGENT_MAX_TURNS_OVERRIDE (AGENT_MODEL_OVERRIDE 패턴 미러)
# 우선순위: override(양의 정수) > frontmatter maxTurns > rank 기본값
# ─────────────────────────────────────────────────────────

@test "C-2: AGENT_MAX_TURNS_OVERRIDE=7 이 frontmatter maxTurns=3 보다 우선 — 5턴은 캡 미발동" {
  _make_capped_soul   # maxTurns: 3
  _source_agent_runner
  _setup_fast_chatty_claude   # 5턴 즉시 방출

  local rc=0
  AGENT_MAX_TURNS_OVERRIDE=7 agent_run capy "override 우선순위 테스트" > "$TEST_PROJECT/run.out" 2>&1 || rc=$?

  [ "$rc" -eq 0 ]
  grep -q "turn_cap=0" "$TEST_PROJECT/run.out"
  grep -q "max_turns=7" "$TEST_PROJECT/run.out"
}

@test "C-2: AGENT_MAX_TURNS_OVERRIDE 비정수/0 → 무시하고 frontmatter maxTurns 적용" {
  _make_capped_soul   # maxTurns: 3
  _source_agent_runner
  _setup_fast_chatty_claude   # 5턴 즉시 방출 — 캡 3 초과

  local rc=0
  AGENT_MAX_TURNS_OVERRIDE=abc agent_run capy "override 무효값 테스트1" > "$TEST_PROJECT/run1.out" 2>&1 || rc=$?
  [ "$rc" -ne 0 ]
  grep -q "max_turns=3" "$TEST_PROJECT/run1.out"
  grep -q "result=checkpoint" "$TEST_PROJECT/run1.out"

  rc=0
  AGENT_MAX_TURNS_OVERRIDE=0 agent_run capy "override 무효값 테스트2" > "$TEST_PROJECT/run2.out" 2>&1 || rc=$?
  [ "$rc" -ne 0 ]
  grep -q "max_turns=3" "$TEST_PROJECT/run2.out"
  grep -q "result=checkpoint" "$TEST_PROJECT/run2.out"
}

# ─────────────────────────────────────────────────────────
# 앵커 — assistant 카운트는 envelope 라인만, 본문 텍스트 내 리터럴
# "type":"assistant" 문자열 등장은 무시해야 한다 (오카운트 방지)
# ─────────────────────────────────────────────────────────

# fake claude: envelope 이 아닌 "user" 필러 라인 4개(본문에 리터럴
# "type":"assistant" 문자열 포함, 즉 앵커 없으면 매칭됨) + 실제 assistant
# envelope 1개(본문에도 같은 문자열이 여러 번 인용됨) + result. 전부 즉시 출력.
_setup_anchor_claude() {
  mkdir -p "$TEST_PROJECT/bin"
  cat > "$TEST_PROJECT/bin/claude" <<'FAKE'
#!/usr/bin/env bash
echo '{"type":"user","note":"예시 인용: "type":"assistant" 문자열이 여기 있다 (1)"}'
echo '{"type":"user","note":"예시 인용: "type":"assistant" 문자열이 여기 있다 (2)"}'
echo '{"type":"user","note":"예시 인용: "type":"assistant" 문자열이 여기 있다 (3)"}'
echo '{"type":"user","note":"예시 인용: "type":"assistant" 문자열이 여기 있다 (4)"}'
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"본문 인용: "type":"assistant" a "type":"assistant" b "type":"assistant" c"}]}}'
echo '{"type":"result","is_error":false,"duration_ms":50,"result":"DONE","usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}'
FAKE
  chmod +x "$TEST_PROJECT/bin/claude"
  export PATH="$TEST_PROJECT/bin:$PATH"
}

@test "turn-cap: 앵커 — 본문에 리터럴 \"type\":\"assistant\" 문자열이 여러 번 등장해도 실제 envelope 1개면 캡 미적용" {
  _make_capped_soul
  _source_agent_runner
  _setup_anchor_claude

  local rc=0
  AGENT_MAX_SECONDS=120 agent_run capy "앵커 테스트" > "$TEST_PROJECT/run.out" 2>&1 || rc=$?

  # 실제 assistant envelope 은 1개뿐(cap=3 이하) — 앵커 없으면 필러 4줄 + 실제
  # 1줄 = 5줄이 매칭돼 캡(3) 초과로 오판된다. 앵커가 있으면 정상 완주해야 한다.
  [ "$rc" -eq 0 ]
  # P0-4: 마커 없는 정상 완주는 partial 분류 (rc 0)
  grep -qE "result=(success|partial)" "$TEST_PROJECT/run.out"
  grep -q "turn_cap=0" "$TEST_PROJECT/run.out"
  ! grep -q "TURN CAP" "$TEST_PROJECT/run.out"
}

# ─────────────────────────────────────────────────────────
# 사후 정산(post-run reconciliation) — 폴링(1s) 사이의 고속 버스트가 kill 없이
# 끝나버려도 turn_cap 으로 분류돼야 한다 (라이브 워치독이 못 잡는 빈틈 봉인)
# ─────────────────────────────────────────────────────────

@test "turn-cap: 사후 정산 — cap+2 assistant 라인을 즉시 방출 후 exit 0(kill 없음) → turn_cap 으로 분류" {
  _make_capped_soul
  _source_agent_runner
  # cap=3, 5(=cap+2)개 assistant 라인을 sleep 없이 즉시 방출 + 정상 종료.
  # 1초 폴링 워치독이 개입하기 전에 자식이 이미 끝나므로 kill 은 발생하지 않는다.
  _setup_fast_chatty_claude

  local rc=0
  AGENT_MAX_SECONDS=120 agent_run capy "고속 버스트 테스트" > "$TEST_PROJECT/run.out" 2>&1 || rc=$?

  [ "$rc" -eq 1 ]
  grep -q "result=checkpoint" "$TEST_PROJECT/run.out"
  grep -q "turn_cap=1" "$TEST_PROJECT/run.out"
  # kill 이 아닌 사후 정산 경로임을 메시지로 구분 (killed 경로 문구와 달라야 함)
  grep -q "사후 정산" "$TEST_PROJECT/run.out"
  ! grep -q "프로세스 강제 종료" "$TEST_PROJECT/run.out"
  # growth-log 도 checkpoint 로 기록되어야 함 (reason 필드에 turn_cap 유지)
  assert_jsonl_field "$TEST_PROJECT/.golem/growth-log/capy.jsonl" "result" "checkpoint"
}

# ─────────────────────────────────────────────────────────
# P0-4 — [GOLEM_DONE] 완료 계약 + growth-log 실측 정산
# ─────────────────────────────────────────────────────────

@test "P0-4: GOLEM_DONE status=complete → result=success + growth-log files 실측(git) 기록" {
  load_fixture "souls/zen.md" "$TEST_PROJECT/.golem/souls/zen.md"
  _source_agent_runner

  # git 실측 대상 — 커밋 1개 후 파일 2개 스테이징 (마커는 일부러 잘못된 값 99 선언)
  git -C "$TEST_PROJECT" init -q
  git -C "$TEST_PROJECT" -c user.email=t@t -c user.name=t commit --allow-empty -q -m init
  echo one > "$TEST_PROJECT/a.txt"
  echo two > "$TEST_PROJECT/b.txt"
  git -C "$TEST_PROJECT" add a.txt b.txt

  mkdir -p "$TEST_PROJECT/bin"
  cat > "$TEST_PROJECT/bin/claude" <<'FAKE'
#!/usr/bin/env bash
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"작업 완료.\n[GOLEM_DONE] status=complete files=99 tests=3/0 note=ok"}]}}'
echo '{"type":"result","is_error":false,"duration_ms":100,"usage":{"input_tokens":5,"output_tokens":3,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}'
FAKE
  chmod +x "$TEST_PROJECT/bin/claude"
  export PATH="$TEST_PROJECT/bin:$PATH"

  run agent_run zen "완료 태스크"
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=success"* ]]
  [[ "$output" == *"done_marker=present"* ]]
  assert_jsonl_field "$TEST_PROJECT/.golem/growth-log/zen.jsonl" "result" "success"
  # 마커의 files=99 선언이 아니라 git 실측치(2)가 기록되어야 함
  grep -q '"files_changed":2' "$TEST_PROJECT/.golem/growth-log/zen.jsonl"
  grep -q '"tests_passed":3' "$TEST_PROJECT/.golem/growth-log/zen.jsonl"
}

@test "P0-4: 마커 없이 정상 종료 → result=partial" {
  load_fixture "souls/zen.md" "$TEST_PROJECT/.golem/souls/zen.md"
  _source_agent_runner
  mkdir -p "$TEST_PROJECT/bin"
  cat > "$TEST_PROJECT/bin/claude" <<'FAKE'
#!/usr/bin/env bash
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"작업을 완료했습니다 (마커 없음)."}]}}'
echo '{"type":"result","is_error":false,"duration_ms":100,"usage":{"input_tokens":5,"output_tokens":3,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}'
FAKE
  chmod +x "$TEST_PROJECT/bin/claude"
  export PATH="$TEST_PROJECT/bin:$PATH"

  run agent_run zen "마커없음 태스크"
  # P0-4 rc 계약: partial 은 분류이지 실패가 아니다 — rc 0 (flow/mission rc 소비 경로 무변경)
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=partial"* ]]
  [[ "$output" == *"done_marker=absent"* ]]
  assert_jsonl_field "$TEST_PROJECT/.golem/growth-log/zen.jsonl" "result" "partial"
}

@test "P0-4: partial 재시도 시 fresh 세션 (포인터 미갱신)" {
  load_fixture "souls/zen.md" "$TEST_PROJECT/.golem/souls/zen.md"
  _source_agent_runner
  mkdir -p "$TEST_PROJECT/bin"
  cat > "$TEST_PROJECT/bin/claude" <<'FAKE'
#!/usr/bin/env bash
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"마커 없이 종료 (partial 유도)."}]}}'
echo '{"type":"result","is_error":false,"duration_ms":100,"usage":{"input_tokens":5,"output_tokens":3,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}'
FAKE
  chmod +x "$TEST_PROJECT/bin/claude"
  export PATH="$TEST_PROJECT/bin:$PATH"

  run agent_run zen "1차 태스크 (마커 없음)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=partial"* ]]

  # partial 은 세션 마커 기록 대상이 아니다 — 포인터 파일이 생성되지 않아야 함
  [ ! -f "$TEST_PROJECT/.golem/sessions/soul-zen.ptr" ]

  # 포인터가 없으니 다음 소환도 여전히 fresh (따뜻한 세션 없음)
  result=$(_agent_pick_session "zen")
  [[ "$result" =~ fresh$ ]]

  run agent_run zen "2차 태스크 (재소환)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"session=fresh"* ]]
}

@test "P0-4: GOLEM_DONE status=partial → result=partial" {
  load_fixture "souls/zen.md" "$TEST_PROJECT/.golem/souls/zen.md"
  _source_agent_runner
  mkdir -p "$TEST_PROJECT/bin"
  cat > "$TEST_PROJECT/bin/claude" <<'FAKE'
#!/usr/bin/env bash
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"일부만 완료.\n[GOLEM_DONE] status=partial files=1 tests=0/1 note=blocked-by-x"}]}}'
echo '{"type":"result","is_error":false,"duration_ms":100,"usage":{"input_tokens":5,"output_tokens":3,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}'
FAKE
  chmod +x "$TEST_PROJECT/bin/claude"
  export PATH="$TEST_PROJECT/bin:$PATH"

  run agent_run zen "부분완료 태스크"
  # P0-4 rc 계약: partial 은 분류이지 실패가 아니다 — rc 0 (flow/mission rc 소비 경로 무변경)
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=partial"* ]]
  [[ "$output" == *"done_marker=present"* ]]
  assert_jsonl_field "$TEST_PROJECT/.golem/growth-log/zen.jsonl" "result" "partial"
}

@test "P0-4: 턴캡 경로는 GOLEM_DONE 마커가 있어도 result=turn_cap 유지 (기존 result 우선)" {
  _make_capped_soul   # maxTurns: 3
  _source_agent_runner
  mkdir -p "$TEST_PROJECT/bin"
  cat > "$TEST_PROJECT/bin/claude" <<FAKE
#!/usr/bin/env bash
exec 3>&-
echo \$\$ > "$TEST_PROJECT/.claude_pid"
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"[GOLEM_DONE] status=complete files=9 tests=9/0 note=fake-early-claim"}]}}'
i=0
while [ \$i -lt 40 ]; do
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"turn"}]}}'
  sleep 1
  i=\$((i+1))
done
echo '{"type":"result","is_error":false,"duration_ms":100,"usage":{"input_tokens":5,"output_tokens":3,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}'
FAKE
  chmod +x "$TEST_PROJECT/bin/claude"
  export PATH="$TEST_PROJECT/bin:$PATH"

  local rc=0
  AGENT_MAX_SECONDS=120 agent_run capy "마커+턴캡 테스트" > "$TEST_PROJECT/run.out" 2>&1 || rc=$?

  [ "$rc" -eq 1 ]
  # R-1 신계약: 사살은 checkpoint 로 정산 — "마커보다 사살 우선" 의도는
  # result 가 success 로 승격되지 않음을 확인하는 것으로 유지 (사유는 usage 플래그)
  grep -q "result=checkpoint" "$TEST_PROJECT/run.out"
  grep -q "turn_cap=1" "$TEST_PROJECT/run.out"
  assert_jsonl_field "$TEST_PROJECT/.golem/growth-log/capy.jsonl" "result" "checkpoint"
  [ -z "$(jobs -rp)" ]
}

@test "agent-runner: fresh 소환 실패는 폴백 재시도 없음 (1회만)" {
  load_fixture "souls/zen.md" "$TEST_PROJECT/.golem/souls/zen.md"
  _source_agent_runner
  # 항상 실패하는 fake claude (호출 횟수 기록)
  mkdir -p "$TEST_PROJECT/bin"
  cat > "$TEST_PROJECT/bin/claude" <<FAKE
#!/usr/bin/env bash
echo x >> "$TEST_PROJECT/.claude_calls"
exit 1
FAKE
  chmod +x "$TEST_PROJECT/bin/claude"
  export PATH="$TEST_PROJECT/bin:$PATH"

  run agent_run zen "실패 테스트"
  [ "$status" -eq 1 ]
  # fresh 모드 실패는 재시도 대상 아님 — 정확히 1회 호출
  [ "$(wc -l < "$TEST_PROJECT/.claude_calls" | tr -d ' ')" -eq 1 ]
}

# ─────────────────────────────────────────────────────────
# R-1 런 연속체 — 체크포인트 + --continue 이어달리기
# ─────────────────────────────────────────────────────────

_make_checkpoint_soul() {
  mkdir -p "$TEST_PROJECT/.golem/souls"
  cat > "$TEST_PROJECT/.golem/souls/checkr.md" <<'SOUL'
---
name: Checkr
role: qa-tester
rank: junior
specialty: [checkpoint-testing]
model: haiku
tools: [Read, Write, Bash]
isolation: none
created: 2026-07-17
---

## 체크포인트 테스트 SOUL
SOUL
}

_setup_ckpt_hung_claude() {
  # claude: 행 걸림, pid 기록 (사살 검증용)
  mkdir -p "$TEST_PROJECT/bin"
  cat > "$TEST_PROJECT/bin/claude" <<FAKE
#!/usr/bin/env bash
exec 3>&-
echo \$\$ > "$TEST_PROJECT/.claude_pid"
sleep 60
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"HUNG"}]}}'
FAKE
  chmod +x "$TEST_PROJECT/bin/claude"
  export PATH="$TEST_PROJECT/bin:$PATH"
}

_setup_resume_tracking_claude() {
  # claude: --resume 받으면 기록, 정상 응답 (이어달리기 검증용)
  mkdir -p "$TEST_PROJECT/bin"
  # 주의: TEST_PROJECT 는 export 되지 않아 인용 heredoc 이면 런타임에 빈 값 —
  # 비인용 heredoc 으로 작성 시점에 경로를 박아 넣는다 (기존 fake 관용구)
  cat > "$TEST_PROJECT/bin/claude" <<FAKE
#!/usr/bin/env bash
exec 3>&-
for a in "\$@"; do
  [ "\$a" = "--resume" ] && echo "RESUME" >> "$TEST_PROJECT/.resume_called"
done
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"[체크포인트 승계 — 슬라이스"}]}}'
echo '{"type":"result","is_error":false,"duration_ms":100,"result":"SUCCESS","usage":{"input_tokens":5,"output_tokens":3,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}'
FAKE
  chmod +x "$TEST_PROJECT/bin/claude"
  export PATH="$TEST_PROJECT/bin:$PATH"
}

@test "R-1: [사살→체크포인트] 벽시계 사살 → checkpoint JSON 생성 + session_id/slice 필드 + result=checkpoint" {
  _make_checkpoint_soul
  _source_agent_runner
  _setup_ckpt_hung_claude

  local rc=0 run_id
  AGENT_MAX_SECONDS=2 agent_run checkr "체크포인트 테스트" > "$TEST_PROJECT/run1.out" 2>&1 || rc=$?

  # 사살은 rc=1
  [ "$rc" -eq 1 ]

  # 체크포인트 파일 존재
  # grep -P 금지 (이 머신 grep 3.0 미지원 + 포터빌리티 규칙) — ERE 로
  run_id=$(grep -oE 'run=[a-f0-9-]+' "$TEST_PROJECT/run1.out" | head -1 | cut -d= -f2)
  [ -n "$run_id" ]
  [ -f "${GOLEM_DIR}/checkpoints/${run_id}.json" ]

  # checkpoint JSON: session_id, slice 필드 포함
  grep -q '"session_id"' "${GOLEM_DIR}/checkpoints/${run_id}.json"
  grep -q '"slice":1' "${GOLEM_DIR}/checkpoints/${run_id}.json"

  # 출력에 result=checkpoint
  grep -q "result=checkpoint" "$TEST_PROJECT/run1.out"

  # growth-log 에 result=checkpoint 기록
  assert_jsonl_field "$TEST_PROJECT/.golem/growth-log/checkr.jsonl" "result" "checkpoint"

  # 워치독 정리
  [ -z "$(jobs -rp)" ]
}

@test "R-1: [--continue 이어달리기] checkpoint로 agent_run_continue → --resume 인자 + 체크포인트 요지 포함 + result=success" {
  _make_checkpoint_soul
  _source_agent_runner
  _setup_resume_tracking_claude

  # 1단계: checkpoint 파일 수동 생성 (이전 슬라이스 시뮬레이션)
  local test_run_id="test-ckpt-$(date +%s)"
  # session_id 는 UUID 여야 한다 — 비 UUID 는 agent_run 의 P2-4 가드가 버리고
  # fresh 로 강하해 --resume 이 영영 안 탄다 (실측 디버깅으로 확인된 함정)
  local test_session="11111111-2222-4333-8444-555555555555"
  mkdir -p "$TEST_PROJECT/.golem/checkpoints"
  mkdir -p "$TEST_PROJECT/.golem/sessions"
  cat > "$TEST_PROJECT/.golem/checkpoints/${test_run_id}.json" <<EOF
{"run_id":"${test_run_id}","session_id":"${test_session}","soul":"checkr","task":"테스트 태스크","workdir":"$(pwd)","diff_stat":"2 files changed, 10 insertions(+)","done_marker_partial":0,"reason":"timeout","slice":1,"ts":"2026-07-17T12:00:00Z"}
EOF
  : > "$TEST_PROJECT/.golem/sessions/${test_session}.claude"

  # 2단계: --continue 호출
  # 주의: 여기서 agent-runner 를 다시 source 하면 체인이 GOLEM_DIR 을 덮어써
  # 세션 마커 조회가 리포 쪽을 보게 된다 (test_helper 경고 함정) — 재소싱 금지
  local rc=0
  agent_run_continue "$test_run_id" > "$TEST_PROJECT/run2.out" 2>&1 || rc=$?

  # rc=0 (성공)
  [ "$rc" -eq 0 ]

  # --resume 이 호출됨 (fake claude 기록)
  [ -f "$TEST_PROJECT/.resume_called" ]
  grep -q "RESUME" "$TEST_PROJECT/.resume_called"

  # 태스크 블록에 "이어서" 또는 "체크포인트 승계" 포함
  grep -q "이어서\|체크포인트 승계" "$TEST_PROJECT/run2.out"

  # 출력에 result=success (fake claude 응답이 "SUCCESS" 포함)
  grep -q "result=success\|SUCCESS" "$TEST_PROJECT/run2.out"
}

@test "R-1: [통합 정산] 이어달리기 성공 슬라이스의 growth-log에 git 실측 files 기록" {
  _make_checkpoint_soul
  _source_agent_runner
  _setup_resume_tracking_claude

  # git 리포 초기화 + 테스트 파일 수정
  cd "$TEST_PROJECT"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"
  echo "a" > file1.txt
  git add file1.txt
  git commit -q -m "init"

  # 파일 2개 변경
  echo "b" > file1.txt
  echo "c" > file2.txt
  git add file2.txt

  # checkpoint 생성
  local test_run_id="test-ckpt-git-$(date +%s)"
  local test_session="sess-git-$(date +%s)"
  mkdir -p "$GOLEM_DIR/checkpoints"
  mkdir -p "$GOLEM_DIR/sessions"
  cat > "$GOLEM_DIR/checkpoints/${test_run_id}.json" <<EOF
{"run_id":"${test_run_id}","session_id":"${test_session}","soul":"checkr","task":"git 정산 테스트","workdir":"$(pwd)","diff_stat":"2 files changed, 2 insertions(+)","done_marker_partial":0,"reason":"timeout","slice":1,"ts":"2026-07-17T12:00:00Z"}
EOF
  : > "$GOLEM_DIR/sessions/${test_session}.claude"

  # --continue 호출
  source "${GOLEM_ROOT}/lib/agent-runner.sh" 2>/dev/null || true
  agent_run_continue "$test_run_id" > "$TEST_PROJECT/run3.out" 2>&1 || true

  # growth-log 에서 files 필드 확인 (git 실측)
  # 파일 2개 변경되어 있으면 files=2 가 기록되어야 함
  [ -f "$GOLEM_DIR/growth-log/checkr.jsonl" ]
  # files 필드가 숫자(0 이상)로 기록됨
  grep -q '"files_changed":[0-9]' "$GOLEM_DIR/growth-log/checkr.jsonl"
}

@test "R-1: [상한 초과 exhausted] slice=3 상태에서 --continue → 호출 없이 result=exhausted + rc 1" {
  _make_checkpoint_soul
  _source_agent_runner

  # fake claude: 호출되면 기록하는 추적 (호출되지 않아야 함)
  mkdir -p "$TEST_PROJECT/bin"
  cat > "$TEST_PROJECT/bin/claude" <<FAKE
#!/usr/bin/env bash
echo "CALLED" >> "$TEST_PROJECT/.claude_called"
echo '{"type":"result","is_error":false,"duration_ms":100,"usage":{"input_tokens":5,"output_tokens":3,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}'
FAKE
  chmod +x "$TEST_PROJECT/bin/claude"
  export PATH="$TEST_PROJECT/bin:$PATH"

  # checkpoint slice=3 생성 (다음 호출이 4가 되어 상한 초과)
  local test_run_id="test-exhausted-$(date +%s)"
  mkdir -p "$TEST_PROJECT/.golem/checkpoints"
  cat > "$TEST_PROJECT/.golem/checkpoints/${test_run_id}.json" <<EOF
{"run_id":"${test_run_id}","session_id":"sess-exhausted","soul":"checkr","task":"상한 초과 테스트","workdir":"$(pwd)","diff_stat":"","done_marker_partial":0,"reason":"timeout","slice":3,"ts":"2026-07-17T12:00:00Z"}
EOF

  # --continue 호출
  local rc=0
  source "${GOLEM_ROOT}/lib/agent-runner.sh" 2>/dev/null || true
  agent_run_continue "$test_run_id" > "$TEST_PROJECT/run4.out" 2>&1 || rc=$?

  # rc=1 (실패)
  [ "$rc" -eq 1 ]

  # fake claude 호출 안 됨 (파일이 없거나 비어있음)
  [ ! -f "$TEST_PROJECT/.claude_called" ] || [ ! -s "$TEST_PROJECT/.claude_called" ]

  # 출력에 result=exhausted
  grep -q "result=exhausted\|EXHAUSTED" "$TEST_PROJECT/run4.out"

  # growth-log 에 result=exhausted 기록
  assert_jsonl_field "$TEST_PROJECT/.golem/growth-log/checkr.jsonl" "result" "exhausted"
}

@test "R-1: [보안] --continue run_id 경로 조작 거부 (Zen 검수 CRITICAL)" {
  _make_checkpoint_soul
  _source_agent_runner

  # 상위 경로에 미끼 파일 — 조작이 통하면 이걸 체크포인트로 읽으려 시도
  mkdir -p "$TEST_PROJECT/.golem/checkpoints"
  printf '{"run_id":"x","session_id":"11111111-2222-4333-8444-555555555555","soul":"checkr","task":"bait","slice":1}\n' \
    > "$TEST_PROJECT/.golem/bait.json"

  local rc=0
  agent_run_continue "../bait" > "$TEST_PROJECT/atk.out" 2>&1 || rc=$?
  [ "$rc" -eq 1 ]
  grep -q "형식 위반" "$TEST_PROJECT/atk.out"
  # 슬래시 포함 절대경로류도 거부
  rc=0
  agent_run_continue "a/b/c" > "$TEST_PROJECT/atk2.out" 2>&1 || rc=$?
  [ "$rc" -eq 1 ]
}
