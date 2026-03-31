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

# SOUL 기반 프롬프트 조립
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

  cat <<PROMPT
[GolemGarden Context — ${SOUL_NAME} (${SOUL_ROLE})]

프로젝트 컨텍스트:
${project_context}

전문 지식 힌트:
${expertise}

이전 작업 이력: ${task_count}건, 성공률 ${success_rate}%
현재 랭크: ${SOUL_RANK}
OMC 에이전트: ${omc_agent} (모델: ${SOUL_MODEL})

이 컨텍스트에서 다음 태스크를 수행하라:
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

# Director(Nex) 태스크 분배 프롬프트
prompt_build_director() {
  local task="$1"
  # 가용 SOUL 목록 수집
  local soul_list=""
  while IFS= read -r soul_file; do
    [ -f "$soul_file" ] || continue
    soul_parse "$soul_file"
    soul_list="${soul_list}
- ${SOUL_NAME} (${SOUL_ROLE}): specialty=[${SOUL_SPECIALTY}], rank=${SOUL_RANK}, model=${SOUL_MODEL}"
  done < <(_all_soul_files)

  cat <<PROMPT
[GolemGarden Director — 태스크 분배]

가용 SOUL 목록:
${soul_list}

태스크: ${task}

다음 기준으로 최적의 SOUL 조합을 선택하고 서브태스크를 분배하라:
1. SOUL의 specialty와 태스크 키워드 매칭
2. SOUL의 rank에 따른 권한 범위 확인
3. 병렬 실행 가능한 서브태스크 식별

출력 형식:
- 서브태스크 1 → {SOUL_NAME}: {설명}
- 서브태스크 2 → {SOUL_NAME}: {설명}
- 실행 모드: {ultrapilot|autopilot|pipeline}
PROMPT
}
