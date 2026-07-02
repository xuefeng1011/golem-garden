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

@test "soul-parser: 글로벌 변수 누설 — strong invariant (effort model-based reset)" {
  load_fixture "souls/nex.md" "$GOLEM_PROJECT/.golem/souls/nex.md"
  source "$GOLEM_ROOT/lib/soul-parser.sh"
  soul_parse "$GOLEM_PROJECT/.golem/souls/nex.md"

  # nex.md에 명시된 effort: high
  [ "$SOUL_NAME" = "Nex" ]
  [ "$SOUL_EFFORT" = "high" ]
  [ "$SOUL_MODEL" = "opus" ]
  local nex_effort="$SOUL_EFFORT"

  # 두 번째 SOUL 파싱: zen.md는 effort 필드 미명시 (model: haiku → 기본값 "low")
  load_fixture "souls/zen.md" "$GOLEM_PROJECT/.golem/souls/zen.md"
  soul_parse "$GOLEM_PROJECT/.golem/souls/zen.md"

  [ "$SOUL_NAME" = "Zen" ]
  [ "$SOUL_MODEL" = "haiku" ]

  # STRONG INVARIANT: zen의 SOUL_EFFORT는 model 기반 기본값(low)이어야 함
  # nex의 "high"가 남아있다면 = 누설 = FAIL
  [ "$SOUL_EFFORT" = "low" ]
  [ "$SOUL_EFFORT" != "$nex_effort" ]
}

@test "soul-parser: SOUL_DISALLOWED_TOOLS — director→non-director 누설 차단 (보안)" {
  load_fixture "souls/nex.md" "$GOLEM_PROJECT/.golem/souls/nex.md"
  source "$GOLEM_ROOT/lib/soul-parser.sh"
  soul_parse "$GOLEM_PROJECT/.golem/souls/nex.md"

  # nex(director)는 disallowed 채움
  [ "$SOUL_ROLE" = "director" ]
  [[ -n "$SOUL_DISALLOWED_TOOLS" ]]
  local nex_disallowed="$SOUL_DISALLOWED_TOOLS"

  # 두 번째 SOUL 파싱: zen은 director 아님 → DISALLOWED_TOOLS는 빈 문자열
  load_fixture "souls/zen.md" "$GOLEM_PROJECT/.golem/souls/zen.md"
  soul_parse "$GOLEM_PROJECT/.golem/souls/zen.md"

  [ "$SOUL_ROLE" = "qa-tester" ]

  # STRONG INVARIANT: zen은 director 아님 → DISALLOWED_TOOLS는 빈 문자열
  # nex의 값이 누설되면 Junior가 권한 차단됨 (보안 회귀)
  [ -z "$SOUL_DISALLOWED_TOOLS" ]
  [ "$SOUL_DISALLOWED_TOOLS" != "$nex_disallowed" ]
}

@test "soul-parser: SOUL_IS_COORDINATOR — director→non-director 누설 차단" {
  load_fixture "souls/nex.md" "$GOLEM_PROJECT/.golem/souls/nex.md"
  source "$GOLEM_ROOT/lib/soul-parser.sh"
  soul_parse "$GOLEM_PROJECT/.golem/souls/nex.md"

  [ "$SOUL_ROLE" = "director" ]
  [ "$SOUL_IS_COORDINATOR" = "true" ]

  # 두 번째 SOUL 파싱: zen은 director 아님 → IS_COORDINATOR는 false
  load_fixture "souls/zen.md" "$GOLEM_PROJECT/.golem/souls/zen.md"
  soul_parse "$GOLEM_PROJECT/.golem/souls/zen.md"

  [ "$SOUL_ROLE" = "qa-tester" ]

  # STRONG INVARIANT: zen은 director 아님 → IS_COORDINATOR는 false
  [ "$SOUL_IS_COORDINATOR" = "false" ]
  [ "$SOUL_IS_COORDINATOR" != "true" ]
}

# ─────────────────────────────────────────────────────────
# rank 기본값 골든 계약 — bash soul_parse ↔ tests/golden/rank-defaults.txt
# (python souls.py 측은 web/gateway/tests/test_rank_defaults_contract.py)
# ─────────────────────────────────────────────────────────

@test "soul-parser: rank 기본값 5종이 골든(rank-defaults.txt)과 일치" {
  golem_load_lib soul-parser
  local golden="${GOLEM_ROOT}/tests/golden/rank-defaults.txt"
  [ -f "$golden" ]

  local line rank g_tools g_turns g_iso
  while IFS='|' read -r rank g_tools g_turns g_iso; do
    [ -z "$rank" ] && continue
    # tools/maxTurns/isolation 미지정 SOUL — rank 기반 기본값 경로
    cat > "$TEST_PROJECT/.golem/souls/gold-${rank}.md" <<SOUL
---
name: Gold${rank}
role: backend-developer
rank: ${rank}
specialty: [golden]
model: sonnet
---
SOUL
    soul_parse "$TEST_PROJECT/.golem/souls/gold-${rank}.md"
    [ "$SOUL_TOOLS" = "$g_tools" ]     || { echo "tools 불일치(${rank}): [$SOUL_TOOLS] != [$g_tools]"; return 1; }
    [ "$SOUL_MAX_TURNS" = "$g_turns" ] || { echo "maxTurns 불일치(${rank}): $SOUL_MAX_TURNS != $g_turns"; return 1; }
    [ "$SOUL_ISOLATION" = "$g_iso" ]   || { echo "isolation 불일치(${rank}): $SOUL_ISOLATION != $g_iso"; return 1; }
  done < "$golden"
}
