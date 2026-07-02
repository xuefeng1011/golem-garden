#!/usr/bin/env bash
# budget.sh — 예산 추적 + 수확체감 감지 + 자동 중단
# Usage: source lib/budget.sh && budget_check ryn

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${GOLEM_ROOT}/lib/soul-parser.sh"
source "${GOLEM_ROOT}/lib/growth-log.sh"

# 기본 설정 (환경변수로 오버라이드 가능)
GOLEM_TOKEN_BUDGET="${GOLEM_TOKEN_BUDGET:-500000}"        # 세션 토큰 상한 (50만)
GOLEM_DOLLAR_BUDGET="${GOLEM_DOLLAR_BUDGET:-10.00}"       # 세션 USD 상한
GOLEM_MAX_STAGNANT_TURNS="${GOLEM_MAX_STAGNANT_TURNS:-3}" # 진전 없는 최대 턴 수
GOLEM_MIN_OUTPUT_TOKENS="${GOLEM_MIN_OUTPUT_TOKENS:-500}" # 최소 출력 토큰 (이 미만이면 진전 없음 판정)

# 예산 상태 파일
_budget_file() {
  echo "${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/budget-state.json"
}

# 예산 초기화 (세션 시작 시)
budget_init() {
  local budget_file=$(_budget_file)
  mkdir -p "$(dirname "$budget_file")"

  cat > "$budget_file" <<BUDGETEOF
{"token_budget":${GOLEM_TOKEN_BUDGET},"dollar_budget":${GOLEM_DOLLAR_BUDGET},"tokens_used":0,"dollars_spent":0.000,"turns":0,"stagnant_turns":0,"status":"ok","started":"$(date -u +%Y-%m-%dT%H:%M:%S 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)"}
BUDGETEOF

  echo "[budget] 초기화: 토큰 상한=${GOLEM_TOKEN_BUDGET}, USD 상한=\$${GOLEM_DOLLAR_BUDGET}"
}

# 사용량 기록 (각 SOUL 턴 완료 후 호출)
# budget_record <soul_name> <tokens_out> <cost_usd>
budget_record() {
  local soul_name="$1"
  local tokens_out="${2:-0}"
  local cost_usd="${3:-0.000}"

  local budget_file=$(_budget_file)
  if [ ! -f "$budget_file" ]; then
    budget_init
  fi

  # 현재 상태 읽기
  local tokens_used=$(grep -o '"tokens_used":[0-9]*' "$budget_file" | cut -d: -f2)
  local dollars_spent=$(grep -o '"dollars_spent":[0-9.]*' "$budget_file" | cut -d: -f2)
  local turns=$(grep -o '"turns":[0-9]*' "$budget_file" | cut -d: -f2)
  local stagnant_turns=$(grep -o '"stagnant_turns":[0-9]*' "$budget_file" | cut -d: -f2)
  tokens_used=${tokens_used:-0}
  dollars_spent=${dollars_spent:-0.000}
  turns=${turns:-0}
  stagnant_turns=${stagnant_turns:-0}

  # 누적
  local new_tokens=$((tokens_used + tokens_out))
  local new_dollars=$(echo "$dollars_spent $cost_usd" | awk '{printf "%.3f", $1+$2}')
  local new_turns=$((turns + 1))

  # 수확체감 감지: 출력 토큰이 최소 임계값 미만이면 stagnant
  local new_stagnant=$stagnant_turns
  if [ "$tokens_out" -lt "$GOLEM_MIN_OUTPUT_TOKENS" ] 2>/dev/null; then
    new_stagnant=$((stagnant_turns + 1))
  else
    new_stagnant=0  # 진전 있으면 리셋
  fi

  # 상태 판정
  local new_status="ok"
  local token_budget=$(grep -o '"token_budget":[0-9]*' "$budget_file" | cut -d: -f2)
  local dollar_budget=$(grep -o '"dollar_budget":[0-9.]*' "$budget_file" | cut -d: -f2)
  token_budget=${token_budget:-$GOLEM_TOKEN_BUDGET}
  dollar_budget=${dollar_budget:-$GOLEM_DOLLAR_BUDGET}

  # 예산 80% 경고
  local token_pct=$((new_tokens * 100 / token_budget))
  if [ "$token_pct" -ge 100 ]; then
    new_status="exceeded"
  elif [ "$token_pct" -ge 80 ]; then
    new_status="warning"
  fi

  # USD 체크
  local dollar_exceeded=$(echo "$new_dollars $dollar_budget" | awk '{print ($1 >= $2) ? "yes" : "no"}')
  if [ "$dollar_exceeded" = "yes" ]; then
    new_status="exceeded"
  fi

  # 수확체감 체크
  if [ "$new_stagnant" -ge "$GOLEM_MAX_STAGNANT_TURNS" ]; then
    new_status="stagnating"
  fi

  # 상태 파일 갱신
  local started=$(grep -o '"started":"[^"]*"' "$budget_file" | sed 's/"started":"//;s/"//')
  cat > "$budget_file" <<BUDGETEOF
{"token_budget":${token_budget},"dollar_budget":${dollar_budget},"tokens_used":${new_tokens},"dollars_spent":${new_dollars},"turns":${new_turns},"stagnant_turns":${new_stagnant},"status":"${new_status}","started":"${started}"}
BUDGETEOF

  # 상태별 출력
  case "$new_status" in
    warning)
      echo "[budget] WARNING: 토큰 ${token_pct}% 사용 (${new_tokens}/${token_budget}), \$${new_dollars}/\$${dollar_budget}"
      ;;
    exceeded)
      echo "[budget] EXCEEDED: 예산 초과! 토큰 ${new_tokens}/${token_budget}, \$${new_dollars}/\$${dollar_budget}"
      echo "[budget] 자동 중단을 권고합니다."
      echo "BUDGET_EXCEEDED"
      ;;
    stagnating)
      echo "[budget] STAGNATING: ${new_stagnant}턴 연속 진전 없음 (최소 출력 ${GOLEM_MIN_OUTPUT_TOKENS}토큰 미만)"
      echo "[budget] ${soul_name}의 작업이 수확체감 상태입니다. 중단 또는 접근법 변경을 권고합니다."
      echo "BUDGET_STAGNATING"
      ;;
  esac
}

# 예산 상태 확인 (중단 필요 여부 반환)
# 반환: ok | warning | exceeded | stagnating
budget_check() {
  local budget_file=$(_budget_file)
  if [ ! -f "$budget_file" ]; then
    echo "ok"
    return
  fi

  grep -o '"status":"[^"]*"' "$budget_file" | sed 's/"status":"//;s/"//'
}

# 예산 상태 표시
budget_status() {
  local budget_file=$(_budget_file)
  if [ ! -f "$budget_file" ]; then
    echo "[budget] 예산 추적 미시작. forge session create 후 자동 활성화됩니다."
    return
  fi

  local token_budget=$(grep -o '"token_budget":[0-9]*' "$budget_file" | cut -d: -f2)
  local dollar_budget=$(grep -o '"dollar_budget":[0-9.]*' "$budget_file" | cut -d: -f2)
  local tokens_used=$(grep -o '"tokens_used":[0-9]*' "$budget_file" | cut -d: -f2)
  local dollars_spent=$(grep -o '"dollars_spent":[0-9.]*' "$budget_file" | cut -d: -f2)
  local turns=$(grep -o '"turns":[0-9]*' "$budget_file" | cut -d: -f2)
  local stagnant_turns=$(grep -o '"stagnant_turns":[0-9]*' "$budget_file" | cut -d: -f2)
  local status=$(grep -o '"status":"[^"]*"' "$budget_file" | sed 's/"status":"//;s/"//')
  local started=$(grep -o '"started":"[^"]*"' "$budget_file" | sed 's/"started":"//;s/"//')

  local token_pct=0
  [ "$token_budget" -gt 0 ] 2>/dev/null && token_pct=$((tokens_used * 100 / token_budget))

  local status_icon="OK"
  case "$status" in
    warning)    status_icon="WARNING" ;;
    exceeded)   status_icon="EXCEEDED" ;;
    stagnating) status_icon="STAGNATING" ;;
  esac

  echo "=== GolemGarden Budget Status ==="
  echo ""
  echo "  상태: ${status_icon}"
  echo "  시작: ${started}"
  echo ""
  echo "  토큰: ${tokens_used} / ${token_budget} (${token_pct}%)"
  echo "  비용: \$${dollars_spent} / \$${dollar_budget}"
  echo "  턴:   ${turns}회"
  echo "  정체: ${stagnant_turns}턴 연속 (임계: ${GOLEM_MAX_STAGNANT_TURNS}턴)"
}

# 예산 리셋 (새 세션 시작 시)
budget_reset() {
  local budget_file=$(_budget_file)
  [ -f "$budget_file" ] && rm -f "$budget_file"
  budget_init
}

# 모델별 비용 추정 (Agent usage → tokens_in, tokens_out, cost_usd)
# Agent 결과는 total_tokens만 제공하므로 입출력 비율 추정 (80:20)
# budget_estimate_cost <model> <total_tokens> <duration_ms> [cache_read] [cache_creation]
# 출력: tokens_in tokens_out cost_usd
#
# P3 경화: 캐시 토큰 단가 반영 — cache_read=입력가의 0.1x, cache_creation=1.25x.
# 기존에는 캐시 토큰이 무가격이라 캐시 위주 런이 $0.000 로 기록돼 비용
# 대시보드가 실지출을 구조적으로 과소집계했다.
budget_estimate_cost() {
  local model="$1"
  local total_tokens="${2:-0}"
  local duration_ms="${3:-0}"
  local cache_read="${4:-0}"
  local cache_creation="${5:-0}"

  # 숫자 방어 (비정수 입력 → 0)
  case "$cache_read" in ''|*[!0-9]*) cache_read=0 ;; esac
  case "$cache_creation" in ''|*[!0-9]*) cache_creation=0 ;; esac

  if [ "$total_tokens" -eq 0 ] 2>/dev/null \
     && [ "$(( cache_read + cache_creation ))" -eq 0 ]; then
    echo "0 0 0.000"; return
  fi

  # 입출력 비율 추정: 80% input, 20% output
  local tokens_in=$(( total_tokens * 80 / 100 ))
  local tokens_out=$(( total_tokens * 20 / 100 ))

  # 모델별 가격 ($/1M tokens) — 근사치. 풀 모델 ID 패턴도 매핑
  # (agent-runner AGENT_MODEL_OVERRIDE 가 claude-* 풀 ID 를 통과시킴).
  local in_price out_price
  case "$model" in
    opus|claude-opus*|*opus-4-8*) in_price=15;  out_price=75 ;;
    sonnet|claude-sonnet*)        in_price=3;   out_price=15 ;;
    haiku|claude-haiku*)          in_price="0.25"; out_price="1.25" ;;
    claude-fable*|fable*)         in_price=15;  out_price=75 ;;  # opus-tier 근사
    *)                            in_price=3;   out_price=15 ;;  # 기본: sonnet
  esac

  # cost = in*price + out*price + cache_read*(0.1x in) + cache_creation*(1.25x in)
  local cost_usd=$(awk "BEGIN {printf \"%.3f\", \
    ($tokens_in * $in_price + $tokens_out * $out_price \
     + $cache_read * $in_price * 0.1 \
     + $cache_creation * $in_price * 1.25) / 1000000}")

  echo "${tokens_in} ${tokens_out} ${cost_usd}"
}
