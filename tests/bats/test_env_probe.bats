#!/usr/bin/env bats
# test_env_probe.bats — lib/env-probe.sh 단위 테스트 (P0-2)
# 커버리지:
#   env_probe_generate — env.md 생성, 필수 섹션, uv 부재 시 pytest 폴백
#   prompt_build_static — env.md 자동 생성 및 프롬프트 주입

load "test_helper"

_source_env_probe() {
  export GOLEM_ROOT
  export GOLEM_DIR="$TEST_PROJECT/.golem"
  # shellcheck source=/dev/null
  source "${GOLEM_ROOT}/lib/env-probe.sh"
  export GOLEM_DIR="$TEST_PROJECT/.golem"
}

# ─────────────────────────────────────────────────────────
# env_probe_generate
# ─────────────────────────────────────────────────────────

@test "env-probe: env_probe_generate — env.md 생성" {
  _source_env_probe
  run env_probe_generate
  [ "$status" -eq 0 ]
  [ -f "$TEST_PROJECT/.golem/env.md" ]
}

@test "env-probe: env.md — 필수 섹션(테스트 명령/도구/함정) 포함" {
  _source_env_probe
  env_probe_generate
  assert_file_contains "$TEST_PROJECT/.golem/env.md" "### 검증된 테스트 실행 명령"
  assert_file_contains "$TEST_PROJECT/.golem/env.md" "### 도구 가용성"
  assert_file_contains "$TEST_PROJECT/.golem/env.md" "### OS 함정 노트"
}

@test "env-probe: env.md — bats 명령 라인 포함" {
  _source_env_probe
  env_probe_generate
  assert_file_contains "$TEST_PROJECT/.golem/env.md" "bats:"
}

@test "env-probe: uv 부재 mock — pytest 폴백 명령 기록됨" {
  _source_env_probe
  # PATH에서 uv 실행파일이 있는 디렉토리만 제외한 격리 PATH 구성
  local filtered_path="" dir old_ifs="$IFS"
  IFS=':'
  for dir in $PATH; do
    [ -x "${dir}/uv" ] && continue
    filtered_path="${filtered_path}${dir}:"
  done
  IFS="$old_ifs"

  PATH="$filtered_path" run env_probe_generate
  [ "$status" -eq 0 ]
  run grep -q "uv run pytest" "$TEST_PROJECT/.golem/env.md"
  [ "$status" -ne 0 ]
  assert_file_contains "$TEST_PROJECT/.golem/env.md" "uv 없음"
}

@test "env-probe: env.md 내용 — 환경 불변 시 재생성해도 byte-stable" {
  _source_env_probe
  env_probe_generate
  local first
  first=$(cat "$TEST_PROJECT/.golem/env.md")
  env_probe_generate
  local second
  second=$(cat "$TEST_PROJECT/.golem/env.md")
  [ "$first" = "$second" ]
}

# ─────────────────────────────────────────────────────────
# prompt_build_static 주입 (env.md 있을 때 / 없을 때)
# ─────────────────────────────────────────────────────────

_write_minimal_soul() {
  local soul_file="$TEST_PROJECT/.golem/souls/testsoul.md"
  mkdir -p "$TEST_PROJECT/.golem/souls"
  cat > "$soul_file" <<'SOUL'
---
name: testsoul
role: tester
rank: junior
model: sonnet
tools: Read, Edit
maxTurns: 10
isolation: none
---

## 프로젝트 컨텍스트

테스트 프로젝트

## 전문 지식

테스트 전문성

## 행동 원칙

원칙
SOUL
}

@test "prompt-builder: env.md 없으면 prompt_build_static 이 자동 생성" {
  export GOLEM_ROOT
  export GOLEM_DIR="$TEST_PROJECT/.golem"
  export GROWTH_DIR="$TEST_PROJECT/.golem/growth-log"
  _write_minimal_soul
  [ ! -f "$TEST_PROJECT/.golem/env.md" ]

  # shellcheck source=/dev/null
  source "${GOLEM_ROOT}/lib/prompt-builder.sh"
  export GOLEM_DIR="$TEST_PROJECT/.golem"
  export GROWTH_DIR="$TEST_PROJECT/.golem/growth-log"

  run prompt_build_static testsoul
  [ "$status" -eq 0 ]
  [ -f "$TEST_PROJECT/.golem/env.md" ]
}

@test "prompt-builder: env.md 있으면 prompt_build_static 출력에 계약 헤더+내용 포함" {
  export GOLEM_ROOT
  export GOLEM_DIR="$TEST_PROJECT/.golem"
  export GROWTH_DIR="$TEST_PROJECT/.golem/growth-log"
  _write_minimal_soul

  # shellcheck source=/dev/null
  source "${GOLEM_ROOT}/lib/env-probe.sh"
  export GOLEM_DIR="$TEST_PROJECT/.golem"
  env_probe_generate

  # shellcheck source=/dev/null
  source "${GOLEM_ROOT}/lib/prompt-builder.sh"
  export GOLEM_DIR="$TEST_PROJECT/.golem"
  export GROWTH_DIR="$TEST_PROJECT/.golem/growth-log"

  run prompt_build_static testsoul
  [ "$status" -eq 0 ]
  [[ "$output" == *"## 실행 환경 계약 (자동 생성 — 이 명령을 그대로 사용하라)"* ]]
  [[ "$output" == *"### 검증된 테스트 실행 명령"* ]]
}

@test "prompt-builder: env.md 없고 env-probe.sh 도 없으면 기존과 동일(계약 블록 미포함)" {
  export GOLEM_ROOT
  export GOLEM_DIR="$TEST_PROJECT/.golem"
  export GROWTH_DIR="$TEST_PROJECT/.golem/growth-log"
  _write_minimal_soul

  # env-probe.sh 를 임시로 안 보이게 — 격리된 가짜 GOLEM_ROOT lib 트리 구성
  local fake_root="$TEST_PROJECT/fake-root"
  mkdir -p "$fake_root/lib"
  cp "${GOLEM_ROOT}/lib/prompt-builder.sh" "$fake_root/lib/"
  cp "${GOLEM_ROOT}/lib/soul-parser.sh" "$fake_root/lib/"
  cp "${GOLEM_ROOT}/lib/growth-log.sh" "$fake_root/lib/"
  # skill-tree.sh 도 없어야 그 블록도 건너뛰므로 함께 복사 안 함

  local real_root="$GOLEM_ROOT"
  export GOLEM_ROOT="$fake_root"
  # shellcheck source=/dev/null
  source "${fake_root}/lib/prompt-builder.sh"
  export GOLEM_DIR="$TEST_PROJECT/.golem"
  export GROWTH_DIR="$TEST_PROJECT/.golem/growth-log"

  run prompt_build_static testsoul
  [ "$status" -eq 0 ]
  [[ "$output" != *"실행 환경 계약"* ]]

  export GOLEM_ROOT="$real_root"
}
