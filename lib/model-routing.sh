#!/usr/bin/env bash
# model-routing.sh — P2-1 역할 기반 모델 라우팅 테이블 (정적, 결정론)
#
# "선택 로직은 스크립트로" (PERF-HARNESS-PLAN §2-4) — 어떤 모델을 쓸지 LLM에게
# 묻지 않고 정적 테이블로 결정한다. Aider/RouteLLM 패턴(§8-4): 정적 if문
# 라우팅이 70%의 이득.
#
# 정책 테이블 (route_model):
#   0) frontmatter model 명시 (비어있지 않고 "auto" 아님) → 그대로 사용 (오버라이드 유지)
#   1) coordinator=true 또는 판단직 role 키워드
#      (director|verifier|coordinator|sage|architect|심판|검증|아키텍트) → opus
#   2) rank expert/master → sonnet
#   3) rank novice/junior + 정형 role 키워드
#      (writer|document|docs|문서|정리|리네임|로그|요약) → haiku
#   4) 그 외 전부 → sonnet
#
# 승급 훅 (재시도 에스컬레이션):
#   GOLEM_MODEL_ESCALATE=1 + AGENT_RETRY_ATTEMPT>=2 (mission-loop/error 경로가
#   설정) → 결정된 모델을 한 티어 승급 (haiku→sonnet→opus, opus는 유지).
#   frontmatter 명시 모델에도 적용된다 — 실패 재시도는 명시값보다 복구가 우선.
#   claude-* 풀 ID는 티어를 알 수 없으므로 승급하지 않는다.
#
# 우선순위 전체 (소비처 agent-runner.sh 기준):
#   AGENT_MODEL_OVERRIDE (env, 최우선) > route_model 결과 > _map_model 기본값

# 내부: 정적 테이블 조회 (frontmatter 미지정/auto 일 때만 호출)
# _route_model_table <role_lc> <rank_lc> <is_coordinator> → 모델 별칭
_route_model_table() {
  local role_lc="$1" rank_lc="$2" is_coord="$3"

  # 1) 판단직 → opus
  if [ "$is_coord" = "true" ]; then
    printf 'opus'
    return 0
  fi
  case "$role_lc" in
    *director*|*verifier*|*coordinator*|*sage*|*architect*|*심판*|*검증*|*아키텍트*)
      printf 'opus'
      return 0 ;;
  esac

  # 2) 상위 실행직 → sonnet
  case "$rank_lc" in
    expert|master)
      printf 'sonnet'
      return 0 ;;
  esac

  # 3) 하위 랭크 + 정형 태스크 role → haiku
  case "$rank_lc" in
    novice|junior)
      case "$role_lc" in
        *writer*|*document*|*docs*|*문서*|*정리*|*리네임*|*로그*|*요약*)
          printf 'haiku'
          return 0 ;;
      esac
      ;;
  esac

  # 4) 기본 → sonnet
  printf 'sonnet'
}

# route_model <frontmatter_model> <role> <rank> <is_coordinator> → 유효 모델
# stdout 으로 모델 별칭(또는 frontmatter 풀 ID)을 출력한다.
route_model() {
  local fm="$1" role="$2" rank="$3" is_coord="$4"
  local model=""

  if [ -n "$fm" ] && [ "$fm" != "auto" ]; then
    # frontmatter 정적 지정 — 오버라이드 유지 (P2-1 계약)
    model="$fm"
  else
    local role_lc rank_lc
    role_lc=$(printf '%s' "$role" | tr '[:upper:]' '[:lower:]')
    rank_lc=$(printf '%s' "$rank" | tr '[:upper:]' '[:lower:]')
    model=$(_route_model_table "$role_lc" "$rank_lc" "$is_coord")
  fi

  # 재시도 에스컬레이션 — 한 티어 승급 (opus/claude-* 는 그대로)
  if [ "${GOLEM_MODEL_ESCALATE:-0}" = "1" ] \
     && [ "${AGENT_RETRY_ATTEMPT:-0}" -ge 2 ] 2>/dev/null; then
    case "$model" in
      haiku)  model="sonnet" ;;
      sonnet) model="opus" ;;
    esac
  fi

  printf '%s\n' "$model"
}
