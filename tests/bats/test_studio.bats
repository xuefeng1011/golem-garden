#!/usr/bin/env bats
# test_studio.bats — Flow Studio (lib/studio.sh, docs/STUDIO_PLAN.md)
#
# agent_run/flow_create/flow_validate/flow_run 은 bats 함수 재정의로 mock 한다.
# _studio_deps 는 command -v 선확인이라 mock 이 있으면 실제 lib 을 소싱하지 않는다
# (lib/mission-loop.sh 의 _mission_loop_deps 와 동일 패턴).
#
# 주의: studio_init 은 ${GOLEM_ROOT}/studios.jsonl (실제 저장소 루트, 프로젝트
# 샌드박스 밖)에 append 한다 — 테스트가 저장소를 오염시키지 않도록 setup/teardown
# 에서 백업·복원한다.

load "test_helper"

_DESIGN_JSON='{"agents":[{"name":"researcher","model":"sonnet","role":"리서처","rules":"근거 남기기"},{"name":"writer","model":"haiku","role":"작성자","rules":""}],"steps":[{"id":"s1","soul":"researcher","task":"자료 조사","deps":[]},{"id":"s2","soul":"writer","task":"{{s1}} 기반 정리","deps":["s1"]}]}'

setup() {
  TEST_PROJECT="$(mktemp -d "${TMPDIR:-/tmp}/studio-test.XXXXXX")"
  export GOLEM_ROOT
  GOLEM_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export GOLEM_DIR="$TEST_PROJECT/.golem" GOLEM_PROJECT="$TEST_PROJECT"
  mkdir -p "$GOLEM_DIR"
  export GOLEM_FLOW_RETRY_BASE_SEC=0

  # 실제 저장소의 studios.jsonl 백업 (없으면 빈 상태로 기억)
  _STUDIOS_JSONL="${GOLEM_ROOT}/studios.jsonl"
  _STUDIOS_JSONL_HAD_FILE=0
  if [ -f "$_STUDIOS_JSONL" ]; then
    _STUDIOS_JSONL_HAD_FILE=1
    cp "$_STUDIOS_JSONL" "$TEST_PROJECT/.studios.jsonl.bak"
  fi

  source "${GOLEM_ROOT}/lib/studio.sh"

  # 기본 mock — 대부분의 테스트는 유효한 flowsmith 응답을 가정한다.
  agent_run() {
    printf '```json\n%s\n```\n' "$_DESIGN_JSON"
    return 0
  }
}

teardown() {
  if [ "$_STUDIOS_JSONL_HAD_FILE" -eq 1 ]; then
    cp "$TEST_PROJECT/.studios.jsonl.bak" "$_STUDIOS_JSONL"
  else
    rm -f "$_STUDIOS_JSONL"
  fi
  rm -rf "$TEST_PROJECT"
}

# ─────────────────────────────────────────────────────────
# 1. studio_init — 스캐폴드 + 멱등
# ─────────────────────────────────────────────────────────

@test "studio: init — 스캐폴드 + studio.json + flowsmith 복사 + 레지스트리, 멱등" {
  local dir="$TEST_PROJECT/studio-init-1"
  run studio_init "$dir" "테스트스튜디오" "테스트 목표"
  [ "$status" -eq 0 ]

  for d in souls flows growth-log mailbox sessions runs; do
    [ -d "$dir/.golem/$d" ]
  done
  [ -d "$dir/output" ]
  [ -f "$dir/studio.json" ]
  grep -q '"name":"테스트스튜디오"' "$dir/studio.json"
  grep -q '"goal":"테스트 목표"' "$dir/studio.json"
  [ -f "$dir/.golem/souls/flowsmith.md" ]

  grep -qF "\"path\":\"${dir}\"" "$GOLEM_ROOT/studios.jsonl"
  local reg_count
  reg_count=$(grep -cF "\"path\":\"${dir}\"" "$GOLEM_ROOT/studios.jsonl")
  [ "$reg_count" -eq 1 ]

  # 두번째 init — 인자 생략, 값 보존 + 레지스트리 중복 없음
  run studio_init "$dir"
  [ "$status" -eq 0 ]
  grep -q '"name":"테스트스튜디오"' "$dir/studio.json"
  grep -q '"goal":"테스트 목표"' "$dir/studio.json"
  reg_count=$(grep -cF "\"path\":\"${dir}\"" "$GOLEM_ROOT/studios.jsonl")
  [ "$reg_count" -eq 1 ]
}

@test "studio: init — 백슬래시 경로도 레지스트리 중복 없음 (이스케이프 불일치 회귀)" {
  # Windows 경로(백슬래시)는 _json_escape 로 저장되는데 dedup 이 RAW 경로를
  # grep 하면 매번 새 라인이 append 되던 결함. Git Bash 에선 cygpath -w 로
  # 실제 Windows 경로를, 그 외에선 백슬래시 세그먼트를 포함한 경로로 재현.
  local bs_dir
  if command -v cygpath >/dev/null 2>&1; then
    bs_dir="$(cygpath -w "$TEST_PROJECT")\\studio-bs"
  else
    bs_dir="$TEST_PROJECT/studio-bs\\seg"
  fi
  # 선생성 — _studio_is_dir_arg 는 '/' 없는 Windows 경로를 [ -d ] 로만 dir 판정
  mkdir -p "$bs_dir"

  run studio_init "$bs_dir" "bs스튜디오" "백슬래시 목표"
  [ "$status" -eq 0 ]
  run studio_init "$bs_dir"
  [ "$status" -eq 0 ]

  # 저장은 이스케이프된 path 로 정확히 1줄 — 구 결함은 init 마다 중복 append(2줄)
  local esc count
  esc=$(_json_escape "$bs_dir")
  count=$(grep -cF "\"path\":\"${esc}\"" "$GOLEM_ROOT/studios.jsonl")
  [ "$count" -eq 1 ]
}

# ─────────────────────────────────────────────────────────
# 2. studio_agent_add — 생성 + growth-log 시드 + 중복 거부
# ─────────────────────────────────────────────────────────

@test "studio: agent-add — soul md 생성 + growth-log 시드, 중복 이름 실패" {
  local dir="$TEST_PROJECT/studio-agent-1"
  run studio_agent_add "$dir" myagent sonnet "테스터" "항상 근거를 남긴다"
  [ "$status" -eq 0 ]

  local soul="$dir/.golem/souls/myagent.md"
  [ -f "$soul" ]
  grep -q '^name: myagent$' "$soul"
  grep -q '^model: sonnet$' "$soul"
  grep -q '^rank: novice$' "$soul"
  grep -q '항상 근거를 남긴다' "$soul"
  [ -f "$dir/.golem/growth-log/myagent.jsonl" ]

  run studio_agent_add "$dir" myagent haiku "다른역할"
  [ "$status" -ne 0 ]
}

# ─────────────────────────────────────────────────────────
# 3. studio_agent_add — 경로 순회/잘못된 이름 거부
# ─────────────────────────────────────────────────────────

@test "studio: agent-add — 경로 순회 이름 거부" {
  local dir="$TEST_PROJECT/studio-agent-2"
  run studio_agent_add "$dir" "../evil" sonnet "role"
  [ "$status" -ne 0 ]
  [ ! -f "$dir/.golem/souls/../evil.md" ]
}

@test "studio: agent-add — role/rules 의 \$()/백틱이 실행되지 않고 리터럴 보존" {
  local dir="$TEST_PROJECT/studio-agent-inj"
  local canary="$TEST_PROJECT/inj-canary"
  run studio_agent_add "$dir" injagent sonnet 'role $(touch '"$canary"')' 'rule `touch '"$canary"'`'
  [ "$status" -eq 0 ]
  [ ! -e "$canary" ]                                  # 확장 실행 안 됨
  grep -qF 'role $(touch' "$dir/.golem/souls/injagent.md"   # 리터럴 보존
  grep -qF 'rule `touch' "$dir/.golem/souls/injagent.md"

  # model 형식 가드 + 개행 가드
  run studio_agent_add "$dir" injagent2 'son net' "role"
  [ "$status" -ne 0 ]
  run studio_agent_add "$dir" injagent3 sonnet "$(printf 'ro\nle')"
  [ "$status" -ne 0 ]
}

# ─────────────────────────────────────────────────────────
# 4. studio_design — 정상 경로
# ─────────────────────────────────────────────────────────

@test "studio: design — 정상 경로(에이전트 2명 + 플로우 생성)" {
  local dir="$TEST_PROJECT/studio-design-1"
  run studio_design "$dir" "시장조사"
  [ "$status" -eq 0 ]

  [ -f "$dir/.golem/souls/researcher.md" ]
  [ -f "$dir/.golem/souls/writer.md" ]
  grep -q '^model: sonnet$' "$dir/.golem/souls/researcher.md"
  grep -q '^model: haiku$' "$dir/.golem/souls/writer.md"

  local flow_id
  flow_id=$(printf '%s\n' "$output" | grep '^  flow_id:' | awk '{print $2}')
  [ -n "$flow_id" ]
  local state="$dir/.golem/flows/${flow_id}/state.json"
  [ -f "$state" ]
  grep -q '"soul":"researcher"' "$state"
  grep -q '"task":"자료 조사"' "$state"
}

@test "studio: design — dir 생략 시 GOLEM_PROJECT 폴백 (게이트웨이 호출 경로)" {
  local dir="$TEST_PROJECT/studio-design-gw"
  studio_init "$dir" "gw" "목표" >/dev/null

  # 게이트웨이: cwd=스튜디오 + GOLEM_PROJECT 설정, goal 하나만 전달
  GOLEM_PROJECT="$dir" run studio_design "소설 창작 팀 구성"
  [ "$status" -eq 0 ]
  [ -f "$dir/.golem/souls/researcher.md" ]
}

@test "studio: design — goal 에 '/' 포함돼도 단일 인자는 goal 로 해석" {
  local dir="$TEST_PROJECT/studio-design-slash"
  studio_init "$dir" "slash" "목표" >/dev/null

  GOLEM_PROJECT="$dir" run studio_design "A/B 테스트 시나리오 플로우"
  [ "$status" -eq 0 ]
  [ -f "$dir/.golem/souls/researcher.md" ]
  # 오인해 만들어진 'A/B ...' 경로가 없어야 한다
  [ ! -d "A/B 테스트 시나리오 플로우" ]
}

@test "studio: design — flowsmith.md 유실 시 템플릿 재복사 후 진행" {
  local dir="$TEST_PROJECT/studio-design-recopy"
  studio_init "$dir" "재복사" "목표" >/dev/null
  rm -f "$dir/.golem/souls/flowsmith.md"

  run studio_design "$dir" "재복사 테스트"
  [ "$status" -eq 0 ]
  [ -f "$dir/.golem/souls/flowsmith.md" ]
}

# ─────────────────────────────────────────────────────────
# 5. studio_design — 1차 실패 → 재질의 1회 → 성공
# ─────────────────────────────────────────────────────────

@test "studio: design — 재질의(1차 garbage, 2차 유효) 후 성공, agent_run 2회 호출" {
  local dir="$TEST_PROJECT/studio-design-2"
  local counter="$TEST_PROJECT/.agent_calls"
  printf '0' > "$counter"

  agent_run() {
    local c
    c=$(cat "$counter"); c=$((c + 1)); printf '%d' "$c" > "$counter"
    if [ "$c" -eq 1 ]; then
      echo "이것은 JSON 코드펜스가 아닙니다"
    else
      printf '```json\n%s\n```\n' "$_DESIGN_JSON"
    fi
    return 0
  }

  run studio_design "$dir" "재질의 테스트"
  [ "$status" -eq 0 ]
  [ "$(cat "$counter")" -eq 2 ]
}

# ─────────────────────────────────────────────────────────
# 6. studio_design — 재질의 후에도 실패 → rc=1
# ─────────────────────────────────────────────────────────

@test "studio: design — 재질의 후에도 실패 시 rc=1" {
  local dir="$TEST_PROJECT/studio-design-3"
  local counter="$TEST_PROJECT/.agent_calls"
  printf '0' > "$counter"

  agent_run() {
    local c
    c=$(cat "$counter"); c=$((c + 1)); printf '%d' "$c" > "$counter"
    echo "항상 JSON 코드펜스가 아닙니다"
    return 0
  }

  run studio_design "$dir" "실패 테스트"
  [ "$status" -eq 1 ]
  [ "$(cat "$counter")" -eq 2 ]
}

# ─────────────────────────────────────────────────────────
# 7. studio_run — 최신 플로우 선택 + rc 전파
# ─────────────────────────────────────────────────────────

@test "studio: run — 기본값은 최신(mtime) 플로우 + rc 전파" {
  local dir="$TEST_PROJECT/studio-run-1"
  mkdir -p "$dir/.golem/flows/flow_old" "$dir/.golem/flows/flow_new"
  printf '{"flow_id":"flow_old","goal":"old","created":"x","status":"pending","steps":[]}' \
    > "$dir/.golem/flows/flow_old/state.json"
  printf '{"flow_id":"flow_new","goal":"new","created":"x","status":"pending","steps":[]}' \
    > "$dir/.golem/flows/flow_new/state.json"
  touch -t 202601010000 "$dir/.golem/flows/flow_old/state.json"
  touch -t 202601020000 "$dir/.golem/flows/flow_new/state.json"

  # flow_create 도 함께 목 처리 — flow_create/flow_validate 는 같은 파일
  # (lib/flow-dag.sh)에서 정의되므로, flow_create 가 안 정의된 상태로 두면
  # _studio_deps 가 그 파일을 재소싱해 flow_validate 목까지 덮어쓴다.
  flow_create() { :; }
  flow_validate() { echo "validate:$1"; return 0; }
  flow_run() { echo "ran:$1"; return 7; }

  run studio_run "$dir"
  [ "$status" -eq 7 ]
  [[ "$output" == *"ran:flow_new"* ]]
}

@test "studio: run — 명시적 flow_id 지정 시 그 플로우 사용" {
  local dir="$TEST_PROJECT/studio-run-2"
  mkdir -p "$dir/.golem/flows/flow_a"
  printf '{"flow_id":"flow_a","goal":"a","created":"x","status":"pending","steps":[]}' \
    > "$dir/.golem/flows/flow_a/state.json"

  flow_create() { :; }
  flow_validate() { return 0; }
  flow_run() { echo "ran:$1"; return 0; }

  run studio_run "$dir" flow_a
  [ "$status" -eq 0 ]
  [[ "$output" == *"ran:flow_a"* ]]
}

@test "studio: run — GOLEM_FLOW_OUTPUT_DIR export + output 디렉토리 생성" {
  local dir="$TEST_PROJECT/studio-run-outdir"
  mkdir -p "$dir/.golem/flows/flow_a"
  printf '{"flow_id":"flow_a","goal":"a","created":"x","status":"pending","steps":[]}' \
    > "$dir/.golem/flows/flow_a/state.json"

  flow_create() { :; }
  flow_validate() { return 0; }
  flow_run() { printf 'OUTDIR:%s\n' "${GOLEM_FLOW_OUTPUT_DIR:-}"; return 0; }

  run studio_run "$dir" flow_a
  [ "$status" -eq 0 ]
  [[ "$output" == *"OUTDIR:${dir}/output"* ]]
  [ -d "$dir/output" ]
}

@test "studio: run — 플로우 없으면 rc=1" {
  local dir="$TEST_PROJECT/studio-run-3"
  studio_init "$dir" >/dev/null
  run studio_run "$dir"
  [ "$status" -eq 1 ]
}

# ─────────────────────────────────────────────────────────
# 8. status/list smoke
# ─────────────────────────────────────────────────────────

@test "studio: status/list — smoke" {
  local dir="$TEST_PROJECT/studio-status-1"
  studio_init "$dir" "상태테스트" "상태 목표" >/dev/null

  run studio_status "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"상태테스트"* ]]
  [[ "$output" == *"상태 목표"* ]]
  [[ "$output" == *"flowsmith"* ]]

  run studio_list
  [ "$status" -eq 0 ]
  [[ "$output" == *"상태테스트"* ]]
  [[ "$output" == *"$dir"* ]]
}

@test "studio: list — 등록 없을 때 안내 문구" {
  rm -f "$GOLEM_ROOT/studios.jsonl"
  run studio_list
  [ "$status" -eq 0 ]
  [[ "$output" == *"등록된 스튜디오 없음"* ]]
}

# ─────────────────────────────────────────────────────────
# 9. 격리 — 현재(가짜) 프로젝트를 오염시키지 않음
# ─────────────────────────────────────────────────────────

@test "studio: 격리 — agent-add/design 은 스튜디오 dir 에만 쓰고 현재 프로젝트 무오염" {
  # GOLEM_PROJECT(현재/가짜 프로젝트)는 setup()에서 TEST_PROJECT로 고정됨.
  mkdir -p "$GOLEM_PROJECT/.golem/souls"
  : > "$GOLEM_PROJECT/.golem/souls/existing.md"
  local before after
  before=$(ls "$GOLEM_PROJECT/.golem/souls" | wc -l | tr -d ' ')

  local dir="$TEST_PROJECT/isolated-studio"
  run studio_agent_add "$dir" myagent sonnet "테스터"
  [ "$status" -eq 0 ]

  after=$(ls "$GOLEM_PROJECT/.golem/souls" | wc -l | tr -d ' ')
  [ "$before" -eq "$after" ]
  [ -f "$dir/.golem/souls/myagent.md" ]
  [ ! -f "$GOLEM_PROJECT/.golem/souls/myagent.md" ]

  run studio_design "$dir" "격리 디자인 테스트"
  [ "$status" -eq 0 ]
  after=$(ls "$GOLEM_PROJECT/.golem/souls" | wc -l | tr -d ' ')
  [ "$before" -eq "$after" ]
  [ ! -f "$GOLEM_PROJECT/.golem/souls/researcher.md" ]
  [ -f "$dir/.golem/souls/researcher.md" ]
}
