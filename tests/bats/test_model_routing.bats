#!/usr/bin/env bats
# test_model_routing.bats — P2-1 역할 기반 모델 라우팅 테이블 (lib/model-routing.sh)
# 정책: frontmatter 명시 우선 → coordinator/판단직 opus → expert/master sonnet
#       → novice/junior 정형직 haiku → 기본 sonnet. 재시도 승급 훅 포함.

load "test_helper"

_source_routing() {
  # shellcheck source=/dev/null
  source "${GOLEM_ROOT}/lib/model-routing.sh"
}

_source_agent_runner() {
  # shellcheck source=/dev/null
  source "${GOLEM_ROOT}/lib/agent-runner.sh"
  export GOLEM_DIR="$TEST_PROJECT/.golem"
  export GROWTH_DIR="$TEST_PROJECT/.golem/growth-log"
}

# ─────────────────────────────────────────────────────────
# 0) frontmatter 명시 우선 (오버라이드 유지)
# ─────────────────────────────────────────────────────────

@test "routing: frontmatter haiku 명시 → 판단직 role 이어도 haiku 유지" {
  _source_routing
  result=$(route_model "haiku" "verifier" "master" "false")
  [ "$result" = "haiku" ]
}

@test "routing: frontmatter claude-* 풀 ID → 그대로 통과" {
  _source_routing
  result=$(route_model "claude-opus-4-8" "backend-developer" "junior" "false")
  [ "$result" = "claude-opus-4-8" ]
}

# ─────────────────────────────────────────────────────────
# 1) 빈 값/auto → 정적 테이블 라우팅
# ─────────────────────────────────────────────────────────

@test "routing: auto + coordinator=true → opus" {
  _source_routing
  result=$(route_model "auto" "backend-developer" "senior" "true")
  [ "$result" = "opus" ]
}

@test "routing: 빈 값 + verifier role → opus" {
  _source_routing
  result=$(route_model "" "verifier" "junior" "false")
  [ "$result" = "opus" ]
}

@test "routing: 빈 값 + 한국어 판단직(검증) role → opus" {
  _source_routing
  result=$(route_model "" "코드-검증-담당" "junior" "false")
  [ "$result" = "opus" ]
}

@test "routing: 빈 값 + rank master → sonnet" {
  _source_routing
  result=$(route_model "" "backend-developer" "master" "false")
  [ "$result" = "sonnet" ]
}

@test "routing: 빈 값 + rank expert → sonnet" {
  _source_routing
  result=$(route_model "" "backend-developer" "expert" "false")
  [ "$result" = "sonnet" ]
}

@test "routing: auto + novice + writer role → haiku" {
  _source_routing
  result=$(route_model "auto" "doc-writer" "novice" "false")
  [ "$result" = "haiku" ]
}

@test "routing: 빈 값 + junior + 한국어 정형직(문서) role → haiku" {
  _source_routing
  result=$(route_model "" "문서-정리" "junior" "false")
  [ "$result" = "haiku" ]
}

@test "routing: 빈 값 + senior + 정형직 아닌 role → 기본 sonnet" {
  _source_routing
  result=$(route_model "" "backend-developer" "senior" "false")
  [ "$result" = "sonnet" ]
}

@test "routing: 정형 role 키워드라도 senior 랭크면 haiku 아님 (sonnet)" {
  _source_routing
  result=$(route_model "" "doc-writer" "senior" "false")
  [ "$result" = "sonnet" ]
}

# ─────────────────────────────────────────────────────────
# 2) 재시도 에스컬레이션 (GOLEM_MODEL_ESCALATE=1 + AGENT_RETRY_ATTEMPT>=2)
# ─────────────────────────────────────────────────────────

@test "routing: 에스컬레이션 — haiku 라우팅 결과가 sonnet 으로 승급" {
  _source_routing
  result=$(GOLEM_MODEL_ESCALATE=1 AGENT_RETRY_ATTEMPT=2 \
    route_model "" "doc-writer" "novice" "false")
  [ "$result" = "sonnet" ]
}

@test "routing: 에스컬레이션 — sonnet → opus 승급" {
  _source_routing
  result=$(GOLEM_MODEL_ESCALATE=1 AGENT_RETRY_ATTEMPT=3 \
    route_model "" "backend-developer" "senior" "false")
  [ "$result" = "opus" ]
}

@test "routing: 에스컬레이션 — opus 는 그대로 (최상위 티어)" {
  _source_routing
  result=$(GOLEM_MODEL_ESCALATE=1 AGENT_RETRY_ATTEMPT=2 \
    route_model "" "verifier" "senior" "false")
  [ "$result" = "opus" ]
}

@test "routing: AGENT_RETRY_ATTEMPT=1 은 승급 없음 (재시도 아님)" {
  _source_routing
  result=$(GOLEM_MODEL_ESCALATE=1 AGENT_RETRY_ATTEMPT=1 \
    route_model "" "doc-writer" "novice" "false")
  [ "$result" = "haiku" ]
}

@test "routing: GOLEM_MODEL_ESCALATE 미설정이면 재시도여도 승급 없음" {
  _source_routing
  result=$(AGENT_RETRY_ATTEMPT=2 route_model "" "doc-writer" "novice" "false")
  [ "$result" = "haiku" ]
}

# ─────────────────────────────────────────────────────────
# 3) end-to-end (agent_run --dry-run 배선 검증)
# ─────────────────────────────────────────────────────────

@test "routing e2e: zen(model: haiku 명시) — 라우팅 도입 후에도 model=haiku 유지" {
  load_fixture "souls/zen.md" "$TEST_PROJECT/.golem/souls/zen.md"
  _source_agent_runner
  result=$(agent_run "zen" "테스트 태스크" --dry-run 2>&1)
  [[ "$result" =~ "model=haiku" ]]
}

@test "routing e2e: AGENT_MODEL_OVERRIDE 가 frontmatter/라우팅을 이긴다 (최우선)" {
  load_fixture "souls/zen.md" "$TEST_PROJECT/.golem/souls/zen.md"
  _source_agent_runner
  result=$(AGENT_MODEL_OVERRIDE=opus agent_run "zen" "테스트 태스크" --dry-run 2>&1)
  [[ "$result" =~ "model=opus" ]]
}

@test "routing e2e: model: auto SOUL → 정적 테이블 라우팅 결과가 CLI 인자에 반영" {
  mkdir -p "$TEST_PROJECT/.golem/souls"
  cat > "$TEST_PROJECT/.golem/souls/vera.md" <<'SOUL'
---
name: Vera
role: verifier
rank: senior
specialty: [verification]
model: auto
tools: [Read, Grep]
maxTurns: 40
isolation: none
created: 2026-07-05
---

## 프로젝트 컨텍스트 (프롬프트에 주입됨)
- 역할: verifier
SOUL
  _source_agent_runner
  result=$(agent_run "vera" "판정 태스크" --dry-run 2>&1)
  # verifier 판단직 → opus
  [[ "$result" =~ "model=opus" ]]
}
