#!/usr/bin/env bats
# test_prompt_builder.bats — B-1 role family 전문가 프로토콜 블록 (byte-stable)
# 설계 정본: nex-b4b1.out "(2) B-1" — 3 family(구현직/판단직/QA직) × 랭크 2변형
# (novice/junior=필수, senior+=권고). 매핑에 없는 role 은 블록 생략.

load "test_helper"

_source_prompt_builder() {
  export GOLEM_ROOT
  export GOLEM_DIR="$TEST_PROJECT/.golem"
  export GROWTH_DIR="$TEST_PROJECT/.golem/growth-log"
  # shellcheck source=/dev/null
  source "${GOLEM_ROOT}/lib/prompt-builder.sh"
  export GOLEM_DIR="$TEST_PROJECT/.golem"
  export GROWTH_DIR="$TEST_PROJECT/.golem/growth-log"
}

_write_soul() {
  local name="$1" role="$2" rank="$3"
  local soul_file="$TEST_PROJECT/.golem/souls/${name}.md"
  mkdir -p "$TEST_PROJECT/.golem/souls"
  cat > "$soul_file" <<SOUL
---
name: ${name}
role: ${role}
rank: ${rank}
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

# ─────────────────────────────────────────────────────────
# family × tier — 6 변형
# ─────────────────────────────────────────────────────────

@test "protocol-block: 구현직(backend-developer) + junior → 필수 변형" {
  _write_soul "implj" "backend-developer" "junior"
  _source_prompt_builder
  run prompt_build_static "implj"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[전문가 프로토콜 — 구현직 (필수 출력)]"* ]]
  [[ "$output" == *"착수 전: 수정할 파일 목록을 먼저 선언하라"* ]]
}

@test "protocol-block: 구현직(frontend-developer) + senior → 권고 변형" {
  _write_soul "impls" "frontend-developer" "senior"
  _source_prompt_builder
  run prompt_build_static "impls"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[전문가 프로토콜 — 구현직 (권고)]"* ]]
  [[ "$output" != *"(필수 출력)"* ]]
}

@test "protocol-block: 판단직(director) + junior → 필수 변형" {
  _write_soul "judgej" "director" "junior"
  _source_prompt_builder
  run prompt_build_static "judgej"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[전문가 프로토콜 — 판단직 (필수 출력)]"* ]]
  [[ "$output" == *"1. 가정: 판단의 전제가 되는 가정을 모두 나열하라."* ]]
}

@test "protocol-block: 판단직(knowledge-auditor) + master → 권고 변형" {
  _write_soul "judgem" "knowledge-auditor" "master"
  _source_prompt_builder
  run prompt_build_static "judgem"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[전문가 프로토콜 — 판단직 (권고)]"* ]]
  [[ "$output" != *"(필수 출력)"* ]]
}

@test "protocol-block: QA직(qa-tester) + novice → 필수 변형" {
  _write_soul "qan" "qa-tester" "novice"
  _source_prompt_builder
  run prompt_build_static "qan"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[전문가 프로토콜 — QA직 (필수 출력)]"* ]]
  [[ "$output" == *"1. 재현 먼저:"* ]]
}

@test "protocol-block: QA직(security-auditor) + lead → 권고 변형" {
  _write_soul "qal" "security-auditor" "lead"
  _source_prompt_builder
  run prompt_build_static "qal"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[전문가 프로토콜 — QA직 (권고)]"* ]]
  [[ "$output" != *"(필수 출력)"* ]]
}

# ─────────────────────────────────────────────────────────
# 미지 role → 블록 생략
# ─────────────────────────────────────────────────────────

@test "protocol-block: 매핑에 없는 role → 블록 전체 생략" {
  _write_soul "unmapped" "flowsmith-architect" "junior"
  _source_prompt_builder
  run prompt_build_static "unmapped"
  [ "$status" -eq 0 ]
  [[ "$output" != *"[전문가 프로토콜"* ]]
}

# ─────────────────────────────────────────────────────────
# byte-stable — 같은 SOUL 이면 2회 호출 결과가 완전히 동일
# ─────────────────────────────────────────────────────────

@test "protocol-block: byte-stable — 동일 SOUL 2회 호출 diff 없음" {
  _write_soul "stablej" "backend-developer" "junior"
  _source_prompt_builder
  local first second
  first=$(prompt_build_static "stablej")
  second=$(prompt_build_static "stablej")
  [ "$first" = "$second" ]
}
