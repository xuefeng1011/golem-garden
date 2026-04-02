#!/bin/bash
# prompt-builder.sh — SOUL 컨텍스트를 OMC 에이전트 프롬프트로 조립
# Usage: source lib/prompt-builder.sh && prompt_build ryn "인증 API 구현"

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${GOLEM_ROOT}/lib/soul-parser.sh"
source "${GOLEM_ROOT}/lib/growth-log.sh"

# SOUL.md에서 프롬프트 주입 섹션 추출 (Windows Git Bash 호환)
# 섹션 헤더가 "## 전문 지식 (컨텍스트 힌트로 주입)" 처럼 부가 텍스트를 포함할 수 있으므로 부분 매칭
_extract_section() {
  local file="$1"
  local section="$2"
  awk -v sec="$section" '
    /^## / && index($0, sec) > 0 { found=1; next }
    found && /^## / { exit }
    found { print }
  ' "$file" | tr -d '\r'
}

# SOUL 기반 프롬프트 조립 (캐시 최적화: 공통 접두사 + SOUL별 접미사)
prompt_build() {
  local soul_name="$1"
  local task="$2"
  local soul_file=$(_resolve_soul_file "$soul_name")

  if [ ! -f "$soul_file" ]; then
    echo "[ERROR] SOUL 파일 없음: ${soul_file}" >&2
    return 1
  fi

  soul_parse "$soul_file"

  local task_count=$(growth_log_task_count "$soul_name")
  local success_rate=$(growth_log_success_rate "$soul_name")
  local omc_agent=$(soul_to_omc_agent "$SOUL_ROLE")

  # 프로젝트 컨텍스트 추출
  local project_context=$(_extract_section "$soul_file" "프로젝트 컨텍스트")
  local expertise=$(_extract_section "$soul_file" "전문 지식")
  local principles=$(_extract_section "$soul_file" "행동 원칙")

  # 새 frontmatter 필드 (기본값은 soul_parse에서 설정됨)
  local tools="${SOUL_TOOLS:-Read, Edit, Grep, Glob}"
  local max_turns="${SOUL_MAX_TURNS:-20}"
  local isolation="${SOUL_ISOLATION:-none}"

  # 랭크 기반 권한 제약
  local rank_constraint=""
  case "$SOUL_RANK" in
    novice)
      rank_constraint="[랭크 제약: Novice] 단일 파일 수정만 허용. 멀티파일 변경 시 파일별로 나누어 요청하라. 작업 완료 후 리뷰 필수."
      ;;
    junior)
      rank_constraint="[랭크 제약: Junior] 멀티파일 수정 가능. 테스트 코드 작성 필수. 작업 완료 후 리뷰 필수."
      ;;
    senior)
      rank_constraint="[랭크 제약: Senior] 아키텍처 판단 가능. 리뷰 선택적."
      ;;
    lead)
      rank_constraint="[랭크 제약: Lead] 태스크 위임 가능. 아키텍처 결정권 보유."
      ;;
    master)
      rank_constraint="[랭크 제약: Master] 모든 권한. 리뷰 면제."
      ;;
  esac

  # === 캐시 최적화 구조 ===
  # Block 1: 공통 접두사 (모든 SOUL 동일 → API 캐시 히트)
  # Block 2: SOUL별 접미사 (개별 차이만 → 캐시 미스 최소화)

  cat <<PROMPT
[GolemGarden — Project Context (Cache-Optimized Common Block)]

프로젝트 컨텍스트:
${project_context}

공통 규칙:
- 코드 품질: 함수 50줄 이하, 파일 800줄 이하
- 테스트: 단위 테스트 동반 필수
- 보안: 하드코딩 시크릿 금지, 입력 검증 필수
- Git: conventional commits 형식

---

[GolemGarden — SOUL Context: ${SOUL_NAME} (${SOUL_ROLE})]

전문 지식:
${expertise}

행동 원칙:
${principles}

${rank_constraint}

이전 작업 이력: ${task_count}건, 성공률 ${success_rate}%
현재 랭크: ${SOUL_RANK}
허용 도구: [${tools}]
최대 턴: ${max_turns}
격리 모드: ${isolation}
OMC 에이전트: ${omc_agent} (모델: ${SOUL_MODEL})

이 컨텍스트와 행동 원칙을 준수하여 다음 태스크를 수행하라:
${task}
PROMPT
}

# 리뷰어 전용 프롬프트 조립
prompt_build_review() {
  local reviewer_name="$1"
  local worker_name="$2"
  local target="$3"
  local reviewer_file=$(_resolve_soul_file "$reviewer_name")
  local worker_file=$(_resolve_soul_file "$worker_name")

  soul_parse "$reviewer_file"
  local reviewer_role="$SOUL_ROLE"
  local reviewer_specialty="$SOUL_SPECIALTY"
  local reviewer_rank="$SOUL_RANK"

  soul_parse "$worker_file"
  local worker_role="$SOUL_ROLE"
  local worker_rank="$SOUL_RANK"

  local expertise=$(_extract_section "$reviewer_file" "전문 지식")

  cat <<PROMPT
[GolemGarden Review — ${reviewer_name} (${reviewer_role})]

리뷰 관점:
- 전문 분야: ${reviewer_specialty}
- 리뷰어 랭크: ${reviewer_rank}

전문 지식 기반 체크포인트:
${expertise}

작업자: ${worker_name} (${worker_role}), Rank: ${worker_rank}
리뷰 대상: ${target}

위 전문 지식과 관점을 기반으로 코드를 리뷰하라.
버그, 성능, 보안, 컨벤션 준수를 중점 확인.
PROMPT
}

# forge-board.md에서 팀 멤버 이름 추출
_board_members() {
  local board_file="${GOLEM_DIR}/forge-board.md"
  if [ -f "$board_file" ]; then
    grep "^|" "$board_file" | grep -v "^| SOUL\|^| ---\|^|---" | awk -F'|' '{gsub(/^ +| +$/, "", $2); print $2}' | tr -d '\r'
  fi
}

# Director(Nex) Coordinator Protocol 프롬프트
prompt_build_director() {
  local task="$1"
  # forge-board에 팀이 있으면 해당 멤버만, 없으면 전체
  local board_members=$(_board_members)
  local soul_list=""
  while IFS= read -r soul_file; do
    [ -f "$soul_file" ] || continue
    soul_parse "$soul_file"
    # forge-board가 있으면 등록된 SOUL만 포함
    if [ -n "$board_members" ]; then
      echo "$board_members" | grep -qi "$SOUL_NAME" || continue
    fi
    local perm=""
    case "$SOUL_RANK" in
      novice) perm="단일파일, 리뷰필수" ;;
      junior) perm="멀티파일, 리뷰필수" ;;
      senior) perm="아키텍처가능, 리뷰선택" ;;
      lead|master) perm="전체권한" ;;
    esac
    soul_list="${soul_list}
- ${SOUL_NAME} (${SOUL_ROLE}): specialty=[${SOUL_SPECIALTY}], rank=${SOUL_RANK}(${perm}), model=${SOUL_MODEL}, tools=[${SOUL_TOOLS}], maxTurns=${SOUL_MAX_TURNS}, isolation=${SOUL_ISOLATION}"
  done < <(_all_soul_files)

  cat <<PROMPT
[GolemGarden Director Protocol — Coordinator]

당신은 Coordinator입니다. 직접 코드를 작성하지 않습니다.

## 사용 가능 도구
- Agent: SOUL을 소환하여 작업 위임
- SendMessage: 진행 중인 SOUL에게 추가 지시
- TaskStop: SOUL 작업 중단

## 워크플로
1. **분석**: 작업을 이해하고 필요한 전문성 파악
2. **분배**: 최적의 SOUL 선택 (specialty 매칭 + rank 고려)
3. **종합**: SOUL 결과를 검토하고 통합
4. **검증**: QA SOUL(Zen)에게 리뷰 위임

## 병렬화 규칙
- 읽기 작업: 자유롭게 병렬화
- 쓰기 작업: 파일 영역별 직렬화
- 리뷰: 구현 완료 후에만

## 에러 복구 프로토콜
- SOUL 실패 1회: 같은 SOUL에 실패 원인 주입 후 재시도
- SOUL 실패 2회: 다른 SOUL에 위임 (specialty 매칭)
- SOUL 실패 3회: 에스컬레이션 (사용자에게 보고)

## 비용 효율
- haiku로 충분한 작업은 haiku SOUL에 배정
- 병렬 SOUL 소환 시 공통 프롬프트 접두사 유지 (캐시 최적화)

## 가용 SOUL 목록
${soul_list}

## 태스크
${task}

다음 기준으로 최적의 SOUL 조합을 선택하고 서브태스크를 분배하라:
1. SOUL의 specialty와 태스크 키워드 매칭
2. SOUL의 rank에 따른 도구 권한(tools) 확인
3. 병렬 실행 가능한 서브태스크 식별
4. 격리(isolation) 필요 여부 판단

출력 형식:
- 서브태스크 1 → {SOUL_NAME}: {설명} [isolation={mode}, model={model}]
- 서브태스크 2 → {SOUL_NAME}: {설명} [isolation={mode}, model={model}]
- 실행 모드: {ultrapilot|autopilot|pipeline}
- 예상 비용: {model별 대략 비용}
PROMPT
}
