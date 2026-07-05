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

# rank/effort 포함 설계 (P3-4) — writer 는 rank 만 지정(effort 생략 → 라인 미기록)
_DESIGN_JSON_RANKED='{"agents":[{"name":"researcher","model":"sonnet","role":"리서처","rules":"","rank":"senior","effort":"high"},{"name":"writer","model":"haiku","role":"작성자","rules":"","rank":"novice"}],"steps":[{"id":"s1","soul":"researcher","task":"자료 조사","deps":[]},{"id":"s2","soul":"writer","task":"{{s1}} 기반 정리","deps":["s1"]}]}'

# 재설계 (P3-3) — researcher(기존 유지) + editor(신규)
_REDESIGN_JSON='{"agents":[{"name":"researcher","model":"sonnet","role":"리서처","rules":""},{"name":"editor","model":"haiku","role":"편집자","rules":"","rank":"junior","effort":"low"}],"steps":[{"id":"r1","soul":"researcher","task":"보강 조사","deps":[]},{"id":"r2","soul":"editor","task":"{{r1}} 편집","deps":["r1"]}]}'

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

@test "studio: agent-add — specialty 값에서 '[' ']' ',' 정화(role: 라인은 원문 유지)" {
  local dir="$TEST_PROJECT/studio-agent-specialty"
  run studio_agent_add "$dir" specagent sonnet 'DB[관리],백엔드'
  [ "$status" -eq 0 ]

  local soul="$dir/.golem/souls/specagent.md"
  [ -f "$soul" ]
  grep -qF 'role: DB[관리],백엔드' "$soul"

  local specialty_line inner
  specialty_line=$(grep '^specialty:' "$soul")
  inner="${specialty_line#specialty: [}"
  inner="${inner%]}"
  case "$inner" in
    *'['*|*']'*|*','*)
      echo "specialty 내부에 브래킷/쉼표 잔존: $inner" >&2
      false ;;
  esac

  source "${GOLEM_ROOT}/lib/soul-parser.sh"
  run soul_parse "$soul"
  [ "$status" -eq 0 ]
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

@test "studio: run — mtime 동률 시 flow_id 사전순 최댓값을 결정적으로 선택(2회 반복 동일)" {
  local dir="$TEST_PROJECT/studio-run-tie"
  mkdir -p "$dir/.golem/flows/flow_aaa" "$dir/.golem/flows/flow_bbb"
  printf '{"flow_id":"flow_aaa","goal":"a","created":"x","status":"pending","steps":[]}' \
    > "$dir/.golem/flows/flow_aaa/state.json"
  printf '{"flow_id":"flow_bbb","goal":"b","created":"x","status":"pending","steps":[]}' \
    > "$dir/.golem/flows/flow_bbb/state.json"
  touch -t 202601010000 "$dir/.golem/flows/flow_aaa/state.json"
  touch -t 202601010000 "$dir/.golem/flows/flow_bbb/state.json"

  flow_create() { :; }
  flow_validate() { return 0; }
  flow_run() { echo "ran:$1"; return 0; }

  run studio_run "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ran:flow_bbb"* ]]

  run studio_run "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ran:flow_bbb"* ]]
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

# ─────────────────────────────────────────────────────────
# 10. P3-4 — agent-add rank/effort 확장
# ─────────────────────────────────────────────────────────

@test "studio: agent-add — rank/effort 지정 시 frontmatter 반영 (isolation 은 none 고정)" {
  local dir="$TEST_PROJECT/studio-agent-rank"
  run studio_agent_add "$dir" ranked sonnet "검증가" "근거 필수" senior high
  [ "$status" -eq 0 ]

  local soul="$dir/.golem/souls/ranked.md"
  grep -q '^rank: senior$' "$soul"
  grep -q '^effort: high$' "$soul"
  grep -q '^isolation: none$' "$soul"

  # rank/effort 생략 시 — rank 기본 novice + effort 라인 미기록
  run studio_agent_add "$dir" plain sonnet "역할"
  [ "$status" -eq 0 ]
  grep -q '^rank: novice$' "$dir/.golem/souls/plain.md"
  run grep -q '^effort:' "$dir/.golem/souls/plain.md"
  [ "$status" -ne 0 ]
}

@test "studio: agent-add — 잘못된 rank/effort 거부" {
  local dir="$TEST_PROJECT/studio-agent-badrank"
  run studio_agent_add "$dir" bad1 sonnet "역할" "" godlike
  [ "$status" -ne 0 ]
  [ ! -f "$dir/.golem/souls/bad1.md" ]

  run studio_agent_add "$dir" bad2 sonnet "역할" "" senior extreme
  [ "$status" -ne 0 ]
  [ ! -f "$dir/.golem/souls/bad2.md" ]
}

@test "studio: design — flowsmith JSON 의 rank/effort 가 SOUL frontmatter 로 적용" {
  local dir="$TEST_PROJECT/studio-design-rank"
  agent_run() {
    printf '```json\n%s\n```\n' "$_DESIGN_JSON_RANKED"
    return 0
  }

  run studio_design "$dir" "랭크 설계"
  [ "$status" -eq 0 ]
  grep -q '^rank: senior$' "$dir/.golem/souls/researcher.md"
  grep -q '^effort: high$' "$dir/.golem/souls/researcher.md"
  grep -q '^rank: novice$' "$dir/.golem/souls/writer.md"
  run grep -q '^effort:' "$dir/.golem/souls/writer.md"
  [ "$status" -ne 0 ]
}

@test "studio: design 검증 — 잘못된 rank/effort 는 계약 위반 (재질의 트리거)" {
  run _studio_validate_design '{"agents":[{"name":"a","model":"sonnet","rank":"boss"},{"name":"b","model":"haiku"}],"steps":[{"id":"s1","soul":"a","task":"t","deps":[]}]}'
  [ "$status" -eq 1 ]
  run _studio_validate_design '{"agents":[{"name":"a","model":"sonnet","effort":"max"},{"name":"b","model":"haiku"}],"steps":[{"id":"s1","soul":"a","task":"t","deps":[]}]}'
  [ "$status" -eq 1 ]
}

# ─────────────────────────────────────────────────────────
# 11. P3-2 — 팀 프리셋 (templates/studio-presets)
# ─────────────────────────────────────────────────────────

@test "studio: preset list — 빌트인 novel-team/market-research 표시" {
  run studio_preset_list
  [ "$status" -eq 0 ]
  [[ "$output" == *"novel-team"* ]]
  [[ "$output" == *"소설팀"* ]]
  [[ "$output" == *"market-research"* ]]
  [[ "$output" == *"시장조사팀"* ]]
}

@test "studio: preset apply — novel-team 4 souls + 6단계 플로우 생성 (암묵 init)" {
  local dir="$TEST_PROJECT/studio-preset-novel"
  run studio_preset_apply "$dir" novel-team
  [ "$status" -eq 0 ]

  local s
  for s in concept-architect writer consistency-checker editor; do
    [ -f "$dir/.golem/souls/${s}.md" ]
  done
  grep -q '^rank: senior$' "$dir/.golem/souls/concept-architect.md"
  grep -q '^effort: high$' "$dir/.golem/souls/concept-architect.md"
  grep -q '^rank: novice$' "$dir/.golem/souls/editor.md"

  local flow_id
  flow_id=$(printf '%s\n' "$output" | grep '^  flow_id:' | awk '{print $2}')
  [ -n "$flow_id" ]
  local state="$dir/.golem/flows/${flow_id}/state.json"
  [ -f "$state" ]
  [ "$(grep -o '"soul":"' "$state" | wc -l | tr -d ' ')" -eq 6 ]

  # 암묵 init — studio.json 에 프리셋 이름/설명 반영
  grep -q '"name":"소설팀"' "$dir/studio.json"
}

@test "studio: preset apply — 미존재 id rc=1 + 형식 위반 id 거부 (디렉토리 미생성)" {
  local dir="$TEST_PROJECT/studio-preset-x"
  run studio_preset_apply "$dir" no-such-preset
  [ "$status" -eq 1 ]
  run studio_preset_apply "$dir" "../evil"
  [ "$status" -eq 1 ]
  run studio_preset_apply "$dir" "Novel_Team"
  [ "$status" -eq 1 ]
  [ ! -d "$dir/.golem" ]
}

@test "studio: preset 파일 — 계약 검증 + flow_validate_steps 통과 (골든 가드)" {
  _studio_deps
  local f json count=0
  for f in "$GOLEM_ROOT/templates/studio-presets/"*.json; do
    [ -f "$f" ] || continue
    count=$((count + 1))
    json=$(tr -d '\r' < "$f")
    run _studio_validate_design "$json"
    [ "$status" -eq 0 ]
    run flow_validate_steps <<<"$json"
    [ "$status" -eq 0 ]
  done
  [ "$count" -ge 2 ]
}

# ─────────────────────────────────────────────────────────
# 12. P3-3 — studio redesign
# ─────────────────────────────────────────────────────────

@test "studio: redesign — 프롬프트에 로스터+최신 플로우 요약+피드백 포함 (flowsmith 제외)" {
  local dir="$TEST_PROJECT/studio-redesign-1"
  studio_design "$dir" "재설계 준비" >/dev/null

  local prompt_file="$TEST_PROJECT/.redesign_prompt"
  agent_run() {
    printf '%s' "$2" > "$prompt_file"
    printf '```json\n%s\n```\n' "$_DESIGN_JSON"
    return 0
  }

  run studio_redesign "$dir" "편집자를 추가해줘"
  [ "$status" -eq 0 ]
  grep -q -- '- researcher: 리서처' "$prompt_file"
  grep -q -- '- writer: 작성자' "$prompt_file"
  grep -q '편집자를 추가해줘' "$prompt_file"
  # 최신 플로우 단계 요약 (id/soul/task 60자)
  grep -q -- '- s1 (researcher): 자료 조사' "$prompt_file"
  # 로스터에서 flowsmith 는 제외
  run grep -q -- '- flowsmith' "$prompt_file"
  [ "$status" -ne 0 ]
}

@test "studio: redesign — 기존 SOUL 보존 + 신규 생성 + 항상 새 플로우" {
  local dir="$TEST_PROJECT/studio-redesign-2"
  run studio_design "$dir" "초기 설계"
  [ "$status" -eq 0 ]
  local old_flow
  old_flow=$(printf '%s\n' "$output" | grep '^  flow_id:' | awk '{print $2}')
  [ -n "$old_flow" ]

  local res_soul="$dir/.golem/souls/researcher.md"
  local old_state="$dir/.golem/flows/${old_flow}/state.json"
  cp "$res_soul" "$TEST_PROJECT/.researcher.bak"
  cp "$old_state" "$TEST_PROJECT/.old-state.bak"

  agent_run() {
    printf '```json\n%s\n```\n' "$_REDESIGN_JSON"
    return 0
  }

  run studio_redesign "$dir" "편집자 추가"
  [ "$status" -eq 0 ]

  # 기존 SOUL 파일 내용 불변 (재생성 금지)
  cmp -s "$res_soul" "$TEST_PROJECT/.researcher.bak"
  # 신규 에이전트 생성 + rank/effort 반영
  [ -f "$dir/.golem/souls/editor.md" ]
  grep -q '^rank: junior$' "$dir/.golem/souls/editor.md"
  grep -q '^effort: low$' "$dir/.golem/souls/editor.md"

  # 항상 새 플로우 — 기존 state.json 불변 + 새 flow_id
  local new_flow
  new_flow=$(printf '%s\n' "$output" | grep '^  flow_id:' | awk '{print $2}')
  [ -n "$new_flow" ]
  [ "$new_flow" != "$old_flow" ]
  [ -f "$dir/.golem/flows/${new_flow}/state.json" ]
  cmp -s "$old_state" "$TEST_PROJECT/.old-state.bak"

  # 유지/신규 보고
  [[ "$output" == *"유지: researcher"* ]]
  [[ "$output" == *"신규: editor"* ]]
}

@test "studio: redesign — 미초기화 스튜디오 rc=1" {
  run studio_redesign "$TEST_PROJECT/no-such-studio" "피드백"
  [ "$status" -eq 1 ]
}
