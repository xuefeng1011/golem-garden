#!/usr/bin/env bats
# test_eval.bats — lib/eval.sh 골든 스위트 러너 테스트 (오프라인, agent_run 모킹)
#
# 커버리지:
#   a) eval_list — 태스크 5종 발견
#   b) 채점기 유효성 — 정답 픽스처는 pass, 빈 워크스페이스는 fail (채점기 자체 검증)
#   c) eval_run — 모킹된 agent_run 으로 pass/fail 기록 + results.jsonl 스키마
#   d) eval_report — 모델별 집계
#
# 실제 claude 호출 없음. agent_run 을 함수 오버라이드로 대체한다.

load "test_helper"

_source_eval() {
  export GOLEM_ROOT
  export GOLEM_DIR="$TEST_PROJECT/.golem"
  export GOLEM_PROJECT="$TEST_PROJECT"
  # shellcheck source=/dev/null
  source "${GOLEM_ROOT}/lib/eval.sh"
  export GOLEM_DIR="$TEST_PROJECT/.golem"
  export GROWTH_DIR="$TEST_PROJECT/.golem/growth-log"
}

# ─────────────────────────────────────────────────────────
# a) 태스크 발견
# ─────────────────────────────────────────────────────────

@test "eval: eval_list — 골든 태스크 7종 발견 (v1 5종 + v2 hard 2종)" {
  _source_eval
  run eval_list
  [ "$status" -eq 0 ]
  [[ "$output" =~ "bugfix-offbyone" ]]
  [[ "$output" =~ "func-json-escape" ]]
  [[ "$output" =~ "jsonl-append" ]]
  [[ "$output" =~ "doc-readme" ]]
  [[ "$output" =~ "verdict-format" ]]
  [[ "$output" =~ "refactor-dedup" ]]
  [[ "$output" =~ "spec-edgecase" ]]
  [[ "$output" =~ "총 7개" ]]
}

# ─────────────────────────────────────────────────────────
# b) 채점기 유효성 — 정답은 통과해야 한다
# ─────────────────────────────────────────────────────────

@test "eval: bugfix-offbyone 채점기 — 정답 픽스처 pass, setup 원본 fail" {
  _source_eval
  local tdir="${GOLEM_ROOT}/tests/eval/bugfix-offbyone"
  local ws="$TEST_PROJECT/ws"
  mkdir -p "$ws"
  # setup 원본(버그 있는 상태)은 fail 이어야 한다
  bash "${tdir}/setup.sh" "$ws"
  run bash "${tdir}/verify.sh" "$ws"
  [ "$status" -eq 1 ]
  # 정답 작성 → pass
  printf '#!/bin/bash\nn="$1"\nseq 1 "$n"\n' > "${ws}/count.sh"
  run bash "${tdir}/verify.sh" "$ws"
  [ "$status" -eq 0 ]
}

@test "eval: func-json-escape 채점기 — 정답 구현 pass" {
  _source_eval
  local tdir="${GOLEM_ROOT}/tests/eval/func-json-escape"
  local ws="$TEST_PROJECT/ws"
  mkdir -p "$ws"
  bash "${tdir}/setup.sh" "$ws"
  run bash "${tdir}/verify.sh" "$ws"
  [ "$status" -eq 1 ]
  cat > "${ws}/lib.sh" <<'EOF'
#!/bin/bash
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}
EOF
  run bash "${tdir}/verify.sh" "$ws"
  [ "$status" -eq 0 ]
}

@test "eval: jsonl-append 채점기 — 정답 한 줄 pass, 두 줄 fail" {
  _source_eval
  local tdir="${GOLEM_ROOT}/tests/eval/jsonl-append"
  local ws="$TEST_PROJECT/ws"
  mkdir -p "$ws"
  printf '{"task":"eval","result":"success","files_changed":0}\n' > "${ws}/log.jsonl"
  run bash "${tdir}/verify.sh" "$ws"
  [ "$status" -eq 0 ]
  printf '{"task":"eval","result":"success","files_changed":0}\n{"x":1}\n' > "${ws}/log.jsonl"
  run bash "${tdir}/verify.sh" "$ws"
  [ "$status" -eq 1 ]
}

@test "eval: doc-readme 채점기 — 정답 pass, 섹션 순서 위반 fail" {
  _source_eval
  local tdir="${GOLEM_ROOT}/tests/eval/doc-readme"
  local ws="$TEST_PROJECT/ws"
  mkdir -p "$ws"
  printf '# Widget\n\n## Install\n\nnpm i widget\n\n## Usage\n\n```bash\nwidget run\n```\n' > "${ws}/README.md"
  run bash "${tdir}/verify.sh" "$ws"
  [ "$status" -eq 0 ]
  printf '# Widget\n\n## Usage\n\n```bash\nx\n```\n\n## Install\n\ny\n' > "${ws}/README.md"
  run bash "${tdir}/verify.sh" "$ws"
  [ "$status" -eq 1 ]
}

@test "eval: verdict-format 채점기 — 정확한 마커 pass, 변형 fail" {
  _source_eval
  local tdir="${GOLEM_ROOT}/tests/eval/verdict-format"
  local ws="$TEST_PROJECT/ws"
  mkdir -p "$ws"
  printf '[VERDICT: FAIL]\n이유: 실패 테스트 2건 존재\n' > "${ws}/verdict.txt"
  run bash "${tdir}/verify.sh" "$ws"
  [ "$status" -eq 0 ]
  # 마커 변형 (판정은 맞지만 형식 위반) → fail
  printf 'FAIL\n이유: 실패 존재\n' > "${ws}/verdict.txt"
  run bash "${tdir}/verify.sh" "$ws"
  [ "$status" -eq 1 ]
}

# ─────────────────────────────────────────────────────────
# c) eval_run — 모킹 실행 + 기록 스키마
# ─────────────────────────────────────────────────────────

@test "eval: eval_run 모킹 (no-op agent) — fail 기록 + jsonl 스키마" {
  _source_eval
  # 아무것도 하지 않는 에이전트 → 전 태스크 fail
  agent_run() { echo "done"; echo "<usage> soul=mock model=mock result=success tokens_in=1 tokens_out=2 tokens_cache=0 duration_ms=42 timeout=0 max_seconds=300 cost_cap=disabled"; }
  run eval_run --task jsonl-append --soul mock --model mocked
  [ "$status" -eq 1 ]
  [[ "$output" =~ "0/1 pass" ]]
  local rf="$TEST_PROJECT/.golem/eval/results.jsonl"
  [ -f "$rf" ]
  grep -q '"task":"jsonl-append"' "$rf"
  grep -q '"model":"mocked"' "$rf"
  grep -q '"result":"fail"' "$rf"
  grep -q '"duration_ms":42' "$rf"
}

@test "eval: eval_run 모킹 (정답 수행 agent) — pass 기록" {
  _source_eval
  # 모킹 에이전트가 cwd(워크스페이스)에 정답 파일 생성 — cwd 기반 실행 검증
  agent_run() {
    printf '{"task":"eval","result":"success","files_changed":0}\n' > log.jsonl
    echo "<usage> soul=mock model=mock result=success tokens_in=1 tokens_out=2 tokens_cache=0 duration_ms=10 timeout=0 max_seconds=300 cost_cap=disabled"
  }
  run eval_run --task jsonl-append --soul mock --model mocked
  [ "$status" -eq 0 ]
  [[ "$output" =~ "1/1 pass" ]]
  grep -q '"result":"pass"' "$TEST_PROJECT/.golem/eval/results.jsonl"
}

@test "eval: 존재하지 않는 --task → 실행 0건, exit 1" {
  _source_eval
  agent_run() { echo "noop"; }
  run eval_run --task no-such-task
  [ "$status" -eq 1 ]
  [[ "$output" =~ "실행된 태스크 없음" ]]
}

# ─────────────────────────────────────────────────────────
# d) eval_report
# ─────────────────────────────────────────────────────────

@test "eval: eval_report — 모델별 집계" {
  _source_eval
  mkdir -p "$TEST_PROJECT/.golem/eval"
  cat > "$TEST_PROJECT/.golem/eval/results.jsonl" <<'EOF'
{"date":"2026-06-10","task":"a","soul":"ryn","model":"sonnet","result":"pass","duration_ms":1,"tokens_out":1}
{"date":"2026-06-10","task":"b","soul":"ryn","model":"sonnet","result":"fail","duration_ms":1,"tokens_out":1}
{"date":"2026-06-10","task":"a","soul":"ryn","model":"haiku","result":"pass","duration_ms":1,"tokens_out":1}
EOF
  run eval_report
  [ "$status" -eq 0 ]
  [[ "$output" =~ "sonnet" ]]
  [[ "$output" =~ "50%" ]]
  [[ "$output" =~ "100%" ]]
}

@test "eval: eval_report — 기록 없음 시 안내" {
  _source_eval
  run eval_report
  [ "$status" -eq 1 ]
  [[ "$output" =~ "기록 없음" ]]
}

# ─────────────────────────────────────────────────────────
# e) 채점기 CRLF / 경계 강화 회귀 테스트
# ─────────────────────────────────────────────────────────

@test "eval: bugfix-offbyone 채점기 — 정답 출력에 CRLF 섞여도 pass" {
  _source_eval
  local tdir="${GOLEM_ROOT}/tests/eval/bugfix-offbyone"
  local ws="$TEST_PROJECT/ws_crlf"
  mkdir -p "$ws"
  # count.sh 가 CRLF 줄바꿈으로 출력해도 채점기가 pass 해야 한다
  # printf "%d\x0d\n" 으로 실제 CR 바이트를 출력한다
  cat > "${ws}/count.sh" << 'SCRIPT'
#!/bin/bash
n="$1"
for i in $(seq 1 "$n"); do printf "%d\x0d\n" "$i"; done
SCRIPT
  run bash "${tdir}/verify.sh" "$ws"
  [ "$status" -eq 0 ]
}

@test "eval: jsonl-append 채점기 — files_changed:01 은 fail (부분일치 방지)" {
  _source_eval
  local tdir="${GOLEM_ROOT}/tests/eval/jsonl-append"
  local ws="$TEST_PROJECT/ws_boundary"
  mkdir -p "$ws"
  printf '{"task":"eval","result":"success","files_changed":01}\n' > "${ws}/log.jsonl"
  run bash "${tdir}/verify.sh" "$ws"
  [ "$status" -eq 1 ]
}

@test "eval: doc-readme 채점기 — 첫 줄이 '# Widget\r' 여도 pass (CRLF 정규화)" {
  _source_eval
  local tdir="${GOLEM_ROOT}/tests/eval/doc-readme"
  local ws="$TEST_PROJECT/ws_crlf_readme"
  mkdir -p "$ws"
  # CRLF 줄바꿈으로 README.md 작성
  printf '# Widget\r\n\r\n## Install\r\n\r\nnpm i widget\r\n\r\n## Usage\r\n\r\n```bash\r\nwidget run\r\n```\r\n' > "${ws}/README.md"
  run bash "${tdir}/verify.sh" "$ws"
  [ "$status" -eq 0 ]
}
