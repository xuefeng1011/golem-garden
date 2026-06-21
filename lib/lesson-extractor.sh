#!/usr/bin/env bash
# lesson-extractor.sh — 태스크 완료 후 학습 자동 추출
# Hermes Agent의 컨텍스트 압축 학습 추출 패턴을 GolemGarden에 적용.
# 세션 종료 시 또는 forge-team Step 5에서 호출.
#
# Usage:
#   source lib/lesson-extractor.sh
#   lesson_extract ryn "JWT 인증 API 구현" success "AuthController.java,JwtUtil.java" "token,auth"

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${GOLEM_ROOT}/lib/soul-parser.sh"
source "${GOLEM_ROOT}/lib/soul-memory.sh"

# ── 학습 추출 판단 기준 ──
# 단순 CRUD/반복 작업은 기록하지 않음. 아래 조건 중 하나라도 해당하면 "학습 가치 있음"으로 판단:
#
# 1. 버그 수정 (디버깅 과정에서 발견한 패턴)
# 2. 성능 개선 (측정 가능한 개선)
# 3. 라이브러리/프레임워크 주의사항 (문서에 없는 함정)
# 4. 아키텍처 결정 (트레이드오프를 수반한 선택)
# 5. 실패 후 성공 (이전 시도에서 배운 것)
# 6. 새로운 도구/기법 사용 (처음 써본 것)

# 태스크 결과에서 학습 포인트를 추출하는 구조화된 프롬프트 생성
# lesson_extract_prompt <soul_name> <task> <result> <files_changed> <context_hints>
# 출력: forge memory record에 전달할 형식의 학습 데이터
lesson_extract_prompt() {
  local soul_name="$1"
  local task="$2"
  local result="$3"
  local files_changed="${4:-}"
  local context_hints="${5:-}"

  # 실패 태스크는 실패 원인 자체가 학습
  local result_context=""
  if [ "$result" = "fail" ]; then
    result_context="이 태스크는 실패했다. 실패 원인과 회피 방법을 학습으로 추출하라."
  else
    result_context="이 태스크는 성공했다. 의미 있는 기술적 발견만 추출하라."
  fi

  cat <<EXTRACT_PROMPT
[GolemGarden Lesson Extractor]

태스크 완료 후 학습 추출을 수행하라.

SOUL: ${soul_name}
태스크: ${task}
결과: ${result}
변경 파일: ${files_changed}
${context_hints:+컨텍스트: ${context_hints}}

${result_context}

## 추출 기준 (아래 중 하나라도 해당하면 기록)

1. **버그 패턴**: 발견한 버그의 근본 원인 + 해결법
2. **성능 개선**: 측정 가능한 개선 기법
3. **프레임워크 함정**: 문서에 없는 주의사항, 호환성 이슈
4. **아키텍처 결정**: 트레이드오프를 수반한 설계 선택 + 근거
5. **실패 교훈**: 이전 시도에서 배운 회피 패턴
6. **새로운 기법**: 처음 사용한 도구/패턴의 핵심 포인트

## 판단 규칙

- 단순 CRUD, 설정 변경, 타이포 수정 → 학습 없음 (SKIP)
- 이미 알려진 일반 상식 → 학습 없음 (SKIP)
- 프로젝트/도메인 특화 발견 → 학습 가치 있음 (RECORD)

## 출력 형식

학습이 있으면:
LESSON::{lesson_text}::TAGS::{comma_separated_tags}

학습이 없으면 (단순 작업):
SKIP::단순 작업 — 학습 추출 불필요

한 태스크에서 최대 2개까지만 추출. 각각 별도 줄로 출력.
lesson_text는 한 줄, 100자 이내. 구체적 기술 내용만. 감상/평가 금지.
tags는 검색용 키워드 3-5개.
EXTRACT_PROMPT
}

# 추출 결과 파싱 + memory_record 자동 호출
# lesson_parse_and_record <soul_name> <task> <extractor_output>
lesson_parse_and_record() {
  local soul_name="$1"
  local task="$2"
  local output="$3"

  local recorded=0

  # SKIP 판정 먼저 체크
  if echo "$output" | grep -q "^SKIP::"; then
    local skip_reason=$(echo "$output" | grep "^SKIP::" | head -1 | sed 's/^SKIP:://')
    echo "[lesson] ${soul_name}: ${skip_reason}"
    return 0
  fi

  # LESSON:: 라인 파싱 (process substitution으로 서브셸 회피)
  while IFS= read -r line; do
    local lesson=$(echo "$line" | sed 's/^LESSON::\(.*\)::TAGS::.*$/\1/')
    local tags=$(echo "$line" | sed 's/^.*::TAGS::\(.*\)$/\1/')

    if [ -n "$lesson" ] && [ "$lesson" != "$line" ]; then
      memory_record "$soul_name" "$task" "$lesson" "$tags"
      recorded=$((recorded + 1))
    fi
  done < <(echo "$output" | grep "^LESSON::")

  if [ "$recorded" -gt 0 ]; then
    echo "[lesson] ${soul_name}: ${recorded}건 학습 기록됨"
  fi

  return 0
}

# 학습 추출 통계
# lesson_stats <soul_name>
lesson_stats() {
  local soul_name="$1"
  local mem_file="${MEMORY_DIR}/${soul_name}.jsonl"

  if [ ! -f "$mem_file" ]; then
    echo "0 0"
    return
  fi

  local total=$(wc -l < "$mem_file" | tr -d ' \r')
  local this_month=$(grep "\"date\":\"$(date +%Y-%m)" "$mem_file" 2>/dev/null | wc -l | tr -d ' \r')
  echo "${total} ${this_month}"
}

# 태그 빈도 분석 (어떤 영역에서 많이 배우는지)
# lesson_tag_frequency <soul_name>
lesson_tag_frequency() {
  local soul_name="$1"
  local mem_file="${MEMORY_DIR}/${soul_name}.jsonl"

  if [ ! -f "$mem_file" ]; then
    echo "(기억 없음)"
    return
  fi

  echo "=== ${soul_name} 학습 태그 빈도 ==="
  grep -o '"tags":"[^"]*"' "$mem_file" | sed 's/"tags":"//;s/"//' | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sort | uniq -c | sort -rn | head -10 | while read count tag; do
    [ -z "$tag" ] && continue
    printf "  %3d회  %s\n" "$count" "$tag"
  done
}
