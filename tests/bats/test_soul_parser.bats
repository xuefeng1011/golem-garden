#!/usr/bin/env bats
# test_soul_parser.bats — Zen 작성 영역 (placeholder)
# Bolt가 인프라 셋업 완료. Zen이 아래에 실제 테스트를 채운다.
#
# 사용법:
#   load "test_helper"   # setup/teardown/load_fixture 로드
#
# 테스트 예시 (Zen이 채울 것):
#   @test "soul-parser: name 필드 파싱" {
#     load_fixture "souls/nex.md" "$TEST_PROJECT/.golem/souls/nex.md"
#     run bash "$GOLEM_ROOT/lib/soul-parser.sh" get-field "$TEST_PROJECT/.golem/souls/nex.md" name
#     [ "$status" -eq 0 ]
#     [ "$output" = "Nex" ]
#   }

load "test_helper"

@test "soul-parser: name 필드 추출" {
  load_fixture "souls/ryn.md" "$GOLEM_PROJECT/.golem/souls/ryn.md"
  source "$GOLEM_ROOT/lib/soul-parser.sh"
  soul_parse "$GOLEM_PROJECT/.golem/souls/ryn.md"
  [ "$SOUL_NAME" = "Ryn" ]
}

@test "soul-parser: role 필드 추출" {
  load_fixture "souls/ryn.md" "$GOLEM_PROJECT/.golem/souls/ryn.md"
  source "$GOLEM_ROOT/lib/soul-parser.sh"
  soul_parse "$GOLEM_PROJECT/.golem/souls/ryn.md"
  [ "$SOUL_ROLE" = "backend-developer" ]
}

@test "soul-parser: rank 필드 추출" {
  load_fixture "souls/ryn.md" "$GOLEM_PROJECT/.golem/souls/ryn.md"
  source "$GOLEM_ROOT/lib/soul-parser.sh"
  soul_parse "$GOLEM_PROJECT/.golem/souls/ryn.md"
  [ "$SOUL_RANK" = "junior" ]
}

@test "soul-parser: novice rank → 기본 tools (Read, Edit, Grep, Glob)" {
  load_fixture "souls/zen.md" "$GOLEM_PROJECT/.golem/souls/zen.md"
  source "$GOLEM_ROOT/lib/soul-parser.sh"
  soul_parse "$GOLEM_PROJECT/.golem/souls/zen.md"
  [ "$SOUL_RANK" = "novice" ]
  [[ "$SOUL_TOOLS" =~ "Read" ]]
  [[ "$SOUL_TOOLS" =~ "Edit" ]]
  [[ "$SOUL_TOOLS" =~ "Grep" ]]
  [[ "$SOUL_TOOLS" =~ "Glob" ]]
}

@test "soul-parser: junior rank → 확장 tools (Write, Bash 추가)" {
  load_fixture "souls/ryn.md" "$GOLEM_PROJECT/.golem/souls/ryn.md"
  source "$GOLEM_ROOT/lib/soul-parser.sh"
  soul_parse "$GOLEM_PROJECT/.golem/souls/ryn.md"
  [ "$SOUL_RANK" = "junior" ]
  [[ "$SOUL_TOOLS" =~ "Write" ]]
  [[ "$SOUL_TOOLS" =~ "Bash" ]]
}

@test "soul-parser: 명시적 tools → rank 기본값 override" {
  load_fixture "souls/nex.md" "$GOLEM_PROJECT/.golem/souls/nex.md"
  source "$GOLEM_ROOT/lib/soul-parser.sh"
  soul_parse "$GOLEM_PROJECT/.golem/souls/nex.md"
  [[ "$SOUL_TOOLS" =~ "Agent" ]]
  [[ "$SOUL_TOOLS" =~ "SendMessage" ]]
}

@test "soul-parser: director role → coordinator tools 강제 (Agent, TaskCreate)" {
  load_fixture "souls/nex.md" "$GOLEM_PROJECT/.golem/souls/nex.md"
  source "$GOLEM_ROOT/lib/soul-parser.sh"
  soul_parse "$GOLEM_PROJECT/.golem/souls/nex.md"
  [ "$SOUL_ROLE" = "director" ]
  [[ "$SOUL_TOOLS" =~ "Agent" ]]
  [[ "$SOUL_TOOLS" =~ "TaskCreate" ]]
}

@test "soul-parser: 연속 파싱 시 변수 누설 없음" {
  load_fixture "souls/ryn.md" "$GOLEM_PROJECT/.golem/souls/ryn.md"
  source "$GOLEM_ROOT/lib/soul-parser.sh"
  soul_parse "$GOLEM_PROJECT/.golem/souls/ryn.md"
  local first_name="$SOUL_NAME"
  local first_rank="$SOUL_RANK"

  load_fixture "souls/zen.md" "$GOLEM_PROJECT/.golem/souls/zen.md"
  soul_parse "$GOLEM_PROJECT/.golem/souls/zen.md"

  [ "$first_name" = "Ryn" ]
  [ "$SOUL_NAME" = "Zen" ]
  [ "$first_rank" = "junior" ]
  [ "$SOUL_RANK" = "novice" ]
}
