#!/usr/bin/env bats
# test_triage.bats — lib/triage.sh 단위 테스트 (P1 C-1 전반부)
# 커버리지:
#   _triage_explore_files — mock 격리 지점 (grep 실행 없이 파일 목록 주입)
#   _triage_domain_count  — 경로 버킷 → 도메인 수
#   _triage_enum_score    — 열거/접속사 신호
#   _triage_ambiguity     — 모호성 판정 (실제 텍스트)
#   triage_run            — 골든 12건 티어 판정 + TRIAGE 라인 파싱 가능성

load "test_helper"

# ─────────────────────────────────────────────────────────
# 골든 12건 — T0 4 / T1 4 / T2 4
# _triage_explore_files 를 함수 오버라이드로 mock 해 파일 목록을 결정론 주입.
# ─────────────────────────────────────────────────────────

@test "triage: T0-1 — 단일 lib 파일, 구체 태스크" {
  golem_load_lib triage
  _triage_explore_files() { printf '%s\n' "lib/flow.sh"; }
  run triage_run "lib/flow.sh 의 retry 기본값을 1로 바꿔라"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tier=T0"* ]]
}

@test "triage: T0-2 — forge.sh 단일 파일, 라인번호 명시" {
  golem_load_lib triage
  _triage_explore_files() { printf '%s\n' "forge.sh"; }
  run triage_run "forge.sh 의 verb 파싱 버그를 수정하라 (line 42)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tier=T0"* ]]
}

@test "triage: T0-3 — bats 테스트 2개 파일, 동일 도메인" {
  golem_load_lib triage
  _triage_explore_files() { printf '%s\n' "tests/bats/test_triage.bats" "tests/bats/run.sh"; }
  run triage_run "tests/bats/test_triage.bats 에 케이스 하나 추가하라"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tier=T0"* ]]
}

@test "triage: T0-4 — gateway 단일 파일 typo 수정" {
  golem_load_lib triage
  _triage_explore_files() { printf '%s\n' "web/gateway/src/golem_gateway/souls.py"; }
  run triage_run "web/gateway/src/golem_gateway/souls.py 의 typo 를 수정하라"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tier=T0"* ]]
}

@test "triage: T1-1 — lib 파일 4개(파일수 3~8, 단일 도메인)" {
  golem_load_lib triage
  _triage_explore_files() {
    printf '%s\n' "lib/mission.sh" "lib/verify.sh" "lib/budget.sh" "lib/insights.sh"
  }
  run triage_run "lib/mission.sh 와 lib/verify.sh 를 함께 수정해 스텝별 rubric 필드를 추가하라"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tier=T1"* ]]
}

@test "triage: T1-2 — lib+bats 파일 3개(같은 bash 버킷)" {
  golem_load_lib triage
  _triage_explore_files() {
    printf '%s\n' "lib/triage.sh" "lib/explore.sh" "tests/bats/test_triage.bats"
  }
  run triage_run "lib/triage.sh 신설 + tests/bats/test_triage.bats 작성"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tier=T1"* ]]
}

@test "triage: T1-3 — 도메인 2개(파일수는 2, 도메인 경계로 T1)" {
  golem_load_lib triage
  _triage_explore_files() {
    printf '%s\n' "web/gateway/src/golem_gateway/sessions_db.py" "lib/growth-log.sh"
  }
  run triage_run "web/gateway/src/golem_gateway/sessions_db.py 스키마 변경과 lib/growth-log.sh 정합성 맞추기"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tier=T1"* ]]
}

@test "triage: T1-4 — lib 파일 6개(파일수 3~8 상단부)" {
  golem_load_lib triage
  _triage_explore_files() {
    printf '%s\n' "lib/skill-tree.sh" "lib/rank-system.sh" "lib/chemistry.sh" \
      "lib/achievement.sh" "tests/bats/test_skill_tree.bats" "forge.sh"
  }
  run triage_run "lib/skill-tree.sh 에 함수 5개 추가하고 tests/bats/test_skill_tree.bats 갱신, forge.sh dispatch 도 연결"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tier=T1"* ]]
}

@test "triage: T2-1 — 모호성 high (구체 신호 전무)" {
  golem_load_lib triage
  _triage_explore_files() { printf '%s\n' "lib/foo.sh"; }
  run triage_run "리팩터링 좀 해줘"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tier=T2"* ]]
  [[ "$output" == *"ambiguity=high"* ]]
}

@test "triage: T2-2 — 모호성 high (범위 불명확)" {
  golem_load_lib triage
  _triage_explore_files() { printf '%s\n' "lib/foo.sh"; }
  run triage_run "전체 코드베이스를 점검해서 개선해줘"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tier=T2"* ]]
}

@test "triage: T2-3 — 파일수 9개(파일수 임계 초과)" {
  golem_load_lib triage
  _triage_explore_files() {
    printf '%s\n' "lib/soul-parser.sh" "lib/growth-log.sh" "lib/rank-system.sh" \
      "lib/prompt-builder.sh" "lib/error-recovery.sh" "lib/mission.sh" \
      "lib/verify.sh" "lib/insights.sh" "lib/budget.sh"
  }
  run triage_run "lib/ 전역 리팩터: soul-parser.sh, growth-log.sh, rank-system.sh, prompt-builder.sh, error-recovery.sh, mission.sh, verify.sh, insights.sh, budget.sh 전부 정리"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tier=T2"* ]]
  [[ "$output" == *"files=9"* ]]
}

@test "triage: T2-4 — 도메인 3개(bash+python+vue 동시)" {
  golem_load_lib triage
  _triage_explore_files() {
    printf '%s\n' "lib/mission.sh" "web/gateway/src/golem_gateway/main.py" \
      "web/client/src/components/hermes/souls/SoulDetailModal.vue"
  }
  run triage_run "lib/mission.sh 수정 + web/gateway/src/golem_gateway/main.py 수정 + web/client/src/components/hermes/souls/SoulDetailModal.vue 수정"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tier=T2"* ]]
  [[ "$output" == *"domains=3"* ]]
}

# ─────────────────────────────────────────────────────────
# _triage_ambiguity — 실제 텍스트
# ─────────────────────────────────────────────────────────

@test "triage: ambiguity — 모호한 텍스트는 high" {
  golem_load_lib triage
  run _triage_ambiguity "리팩터링 좀 해줘"
  [ "$status" -eq 0 ]
  [ "$output" = "high" ]
}

@test "triage: ambiguity — 구체적 텍스트(파일명+숫자+테스트)는 low" {
  golem_load_lib triage
  run _triage_ambiguity "lib/flow.sh 의 retry 기본값을 1로 바꾸고 bats 테스트 추가"
  [ "$status" -eq 0 ]
  [ "$output" = "low" ]
}

# ─────────────────────────────────────────────────────────
# _triage_domain_count / _triage_enum_score — 단위 테스트
# ─────────────────────────────────────────────────────────

@test "triage: domain_count — bash+python+vue 3개 버킷" {
  golem_load_lib triage
  run _triage_domain_count "$(printf '%s\n' "lib/a.sh" "web/gateway/b.py" "web/client/c.vue")"
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "triage: domain_count — etc 경로는 카운트 제외" {
  golem_load_lib triage
  run _triage_domain_count "$(printf '%s\n' "docs/README.md" "souls/nex.md")"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "triage: enum_score — '+'/쉼표/그리고 신호 누적" {
  golem_load_lib triage
  run _triage_enum_score "a.sh 수정 + b.sh 수정, 그리고 c.sh 도 확인"
  [ "$status" -eq 0 ]
  [ "$output" -ge 3 ]
}

# ─────────────────────────────────────────────────────────
# TRIAGE 라인 파싱 가능성
# ─────────────────────────────────────────────────────────

@test "triage: TRIAGE 라인은 grep 1회로 tier 추출 가능" {
  golem_load_lib triage
  _triage_explore_files() { printf '%s\n' "lib/flow.sh"; }
  run triage_run "lib/flow.sh 의 retry 기본값을 1로 바꿔라"
  [ "$status" -eq 0 ]
  local tier
  tier=$(printf '%s\n' "$output" | grep -o 'tier=T[0-2]' | head -1)
  [ "$tier" = "tier=T0" ]
}

# ─────────────────────────────────────────────────────────
# triage_estimate_turns — C-2 턴 예산 산정 (rank×files 산술)
# ─────────────────────────────────────────────────────────

@test "triage_estimate_turns: novice + 파일 0개 → base(8) + 0 + 2 = 10" {
  golem_load_lib triage
  run triage_estimate_turns novice 0
  [ "$status" -eq 0 ]
  [ "$output" = "10" ]
}

@test "triage_estimate_turns: junior + 파일 4개 → 12 + 12 + 2 = 26" {
  golem_load_lib triage
  run triage_estimate_turns junior 4
  [ "$status" -eq 0 ]
  [ "$output" = "26" ]
}

@test "triage_estimate_turns: senior + 파일 20개 → 상한 60 클램프" {
  golem_load_lib triage
  run triage_estimate_turns senior 20
  [ "$status" -eq 0 ]
  [ "$output" = "60" ]
}

# ─────────────────────────────────────────────────────────
# forge.sh 배선 — dispatch (subprocess)
# ─────────────────────────────────────────────────────────

@test "dispatch: forge.sh triage 가 TRIAGE 라인 출력" {
  run bash "${GOLEM_ROOT}/forge.sh" triage "lib/flow.sh 의 retry 기본값을 1로 바꿔라"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRIAGE tier=T"* ]]
}

# ─────────────────────────────────────────────────────────
# forge_do — T0/T1/T2 기어 분기
# _all_soul_files 를 오버라이드해 SOUL 후보를 결정론 고정.
# agent_run 은 함수 mock (파일 카운터로 run 서브셸 경계 우회).
# ─────────────────────────────────────────────────────────

_do_fixture_souls() {
  mkdir -p "$TEST_PROJECT/fixture_souls"
  cat > "$TEST_PROJECT/fixture_souls/bashy.md" <<'EOF'
---
name: bashy
role: backend-developer
rank: senior
specialty: [bash, posix-shell]
model: sonnet
---
EOF
  cat > "$TEST_PROJECT/fixture_souls/pyer.md" <<'EOF'
---
name: pyer
role: backend-developer
rank: senior
specialty: [python, fastapi]
model: sonnet
---
EOF
  _all_soul_files() { printf '%s\n' "$TEST_PROJECT/fixture_souls/bashy.md" "$TEST_PROJECT/fixture_souls/pyer.md"; }
}

@test "forge_do: T0 경로 — specialty 매칭 SOUL 로 agent_run 1회 호출" {
  golem_load_lib triage
  _do_fixture_souls
  _triage_explore_files() { printf '%s\n' "lib/flow.sh"; }
  agent_run() {
    echo "$1" >> "$TEST_PROJECT/.agent_calls"
    echo "mock-agent:$1"
    return 0
  }

  run forge_do "lib/flow.sh 의 bash 함수를 수정하라"
  [ "$status" -eq 0 ]
  [[ "$output" == *"T0 → SOUL 선택: bashy"* ]]
  [ -f "$TEST_PROJECT/.agent_calls" ]
  [ "$(wc -l < "$TEST_PROJECT/.agent_calls" | tr -d ' ')" -eq 1 ]
  [ "$(cat "$TEST_PROJECT/.agent_calls")" = "bashy" ]
}

@test "forge_do: T1 경로 — 권고 문구만 출력, agent_run 미호출" {
  golem_load_lib triage
  _do_fixture_souls
  _triage_explore_files() {
    printf '%s\n' "lib/mission.sh" "lib/verify.sh" "lib/budget.sh" "lib/insights.sh"
  }
  agent_run() { echo "$1" >> "$TEST_PROJECT/.agent_calls"; return 0; }

  run forge_do "lib/mission.sh 와 lib/verify.sh 를 함께 수정해 스텝별 rubric 필드를 추가하라"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[TRIAGE] T1 판정"* ]]
  [[ "$output" == *"forge build:"* ]]
  [ ! -f "$TEST_PROJECT/.agent_calls" ]
}

@test "forge_do: T2 경로 — nex 분해 JSON → mission 생성(state.json/spec.md)" {
  golem_load_lib triage
  _do_fixture_souls
  _triage_explore_files() { printf '%s\n' "lib/foo.sh"; }
  agent_run() {
    cat <<'RESP'
분해했습니다.
[{"id":"1","soul":"bashy","task":"태스크 A","deps":[]},{"id":"2","soul":"pyer","task":"태스크 B","deps":["1"]}]
RESP
  }

  run forge_do "리팩터링 좀 해줘"
  [ "$status" -eq 0 ]
  [[ "$output" == *"T2 → mission 생성됨:"* ]]
  local mid
  mid=$(printf '%s\n' "$output" | grep -o 'msn_[0-9_]*' | head -1)
  [ -n "$mid" ]
  [ -f "${TEST_PROJECT}/.golem/missions/${mid}/state.json" ]
  [ -f "${TEST_PROJECT}/.golem/missions/${mid}/spec.md" ]
  grep -q '태스크 A' "${TEST_PROJECT}/.golem/missions/${mid}/state.json"
}

@test "forge_do: T2 강등 — nex 가 JSON 미반환 시 T1 권고로 강등" {
  golem_load_lib triage
  _do_fixture_souls
  _triage_explore_files() { printf '%s\n' "lib/foo.sh"; }
  agent_run() { echo "그냥 잡담입니다. 특별한 형식 없음."; }

  run forge_do "리팩터링 좀 해줘"
  [ "$status" -ne 0 ]
  [[ "$output" == *"T2 분해 실패"* ]]
  [[ "$output" == *"[TRIAGE] T1 판정"* ]]
  [ ! -d "${TEST_PROJECT}/.golem/missions" ] || [ -z "$(ls -A "${TEST_PROJECT}/.golem/missions" 2>/dev/null)" ]
}
