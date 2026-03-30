#!/bin/bash
# forge-soul.sh — 커스텀 SOUL 생성기 + 프리셋 라이브러리
# Usage: source lib/forge-soul.sh && soul_create_from_preset backend-developer

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${GOLEM_ROOT}/lib/soul-parser.sh"
source "${GOLEM_ROOT}/lib/growth-log.sh"

# ═══════════════════════════════════════════
# 프리셋 라이브러리 (7개 역할)
# ═══════════════════════════════════════════

# 프리셋 정보 반환: name_pool|default_personality|specialties|expertise|principles
_preset_data() {
  local role="$1"
  case "$role" in
    backend-developer)
      echo "Ryn,Astra,Forge|꼼꼼하고 보수적. 테스트 없으면 불안해한다.|spring-boot, mariadb, rest-api, jpa, clean-architecture|DB 성능 튜닝 및 인덱스 전략|JPA N+1 문제 해결 패턴|RESTful API 설계 원칙|에러 핸들링 > 테스트 커버리지 > 기능 완성|OpenAPI 스펙 선행, 마이그레이션 스크립트 동반"
      ;;
    frontend-developer)
      echo "Kai,Lux,Pixel|감각적이고 UX에 집착한다. 1px도 허투루 넘기지 않는다.|react, typescript, tailwind, nextjs, responsive-design|컴포넌트 설계 및 재사용 패턴|성능 최적화 (lazy loading, code splitting)|접근성(a11y) 표준 준수|UX 완성도 > 성능 > 코드 구조|디자인 시스템 컴포넌트 기반 개발"
      ;;
    devops-engineer)
      echo "Bolt,Cira,Atlas|자동화 중독. 수작업은 죄악이다.|docker, kubernetes, github-actions, terraform, monitoring|Docker 멀티스테이지 빌드, compose orchestration|Kubernetes 배포 전략 (Blue-Green, Canary)|CI/CD 파이프라인 설계 및 최적화|인프라 변경은 반드시 IaC로만|모니터링 없는 배포는 배포가 아님"
      ;;
    qa-tester)
      echo "Zen,Sage,Iris|의심이 많다. 엣지케이스 사냥꾼.|jest, cypress, playwright, testing-library, k6|테스트 전략 수립 (단위/통합/E2E)|성능 테스트 및 부하 테스트|테스트 자동화 파이프라인|모든 경로에 테스트 필수|엣지케이스와 경계값 우선 확인"
      ;;
    data-analyst)
      echo "Nova,Flux,Prism|데이터로 말한다. 시각화가 곧 설득이다.|python, pandas, sql, visualization, statistics|데이터 파이프라인 설계|통계 분석 및 가설 검증|대시보드 설계 및 시각화|데이터 기반 의사결정 우선|재현 가능한 분석 환경 구축"
      ;;
    technical-writer)
      echo "Echo,Quill,Reed|명확한 문서를 쓴다. 독자 관점에서 생각한다.|markdown, openapi, jsdoc, diagram, documentation|API 문서 작성 (OpenAPI/Swagger)|아키텍처 다이어그램 설계|사용자 가이드 및 튜토리얼|독자가 5분 안에 이해할 수 없으면 실패|코드 변경 시 문서 동시 업데이트"
      ;;
    security-auditor)
      echo "Vex,Onyx,Shield|편집증적 보안 감각. 제로트러스트 원칙.|owasp, penetration-testing, crypto, access-control, audit|OWASP Top 10 취약점 분석|인증/인가 아키텍처 리뷰|시크릿 관리 및 암호화 전략|모든 입력은 악의적이라고 가정|최소 권한 원칙 철저 준수"
      ;;
    *)
      echo ""
      return 1
      ;;
  esac
}

# 사용 가능한 프리셋 목록
soul_preset_list() {
  echo "=== SOUL 프리셋 라이브러리 ==="
  echo ""
  printf "%-22s %-18s %s\n" "Role" "Name Pool" "Default Personality"
  printf "%-22s %-18s %s\n" "----" "---------" "-------------------"

  local roles="backend-developer frontend-developer devops-engineer qa-tester data-analyst technical-writer security-auditor"
  for role in $roles; do
    local data=$(_preset_data "$role")
    local names=$(echo "$data" | cut -d'|' -f1)
    local personality=$(echo "$data" | cut -d'|' -f2)
    printf "%-22s %-18s %s\n" "$role" "$names" "$personality"
  done
}

# 프리셋에서 첫 번째 미사용 이름 선택
_pick_name() {
  local name_pool="$1"
  local IFS=','
  for name in $name_pool; do
    name=$(echo "$name" | tr -d ' ')
    local lower_name=$(echo "$name" | tr '[:upper:]' '[:lower:]')
    if [ ! -f "${GOLEM_ROOT}/souls/${lower_name}.md" ]; then
      echo "$name"
      return 0
    fi
  done
  # 모든 이름 사용 중이면 숫자 접미사
  local first=$(echo "$name_pool" | cut -d',' -f1 | tr -d ' ')
  local i=2
  while [ -f "${GOLEM_ROOT}/souls/$(echo "${first}${i}" | tr '[:upper:]' '[:lower:]').md" ]; do
    i=$((i + 1))
  done
  echo "${first}${i}"
}

# ═══════════════════════════════════════════
# SOUL 생성 함수들
# ═══════════════════════════════════════════

# 프리셋 기반 SOUL 자동 생성
soul_create_from_preset() {
  local role="$1"
  local custom_name="${2:-}"
  local custom_model="${3:-sonnet}"

  local data=$(_preset_data "$role")
  if [ -z "$data" ]; then
    echo "[forge-soul] ERROR: 알 수 없는 프리셋: ${role}"
    echo "사용 가능: backend-developer, frontend-developer, devops-engineer, qa-tester, data-analyst, technical-writer, security-auditor"
    return 1
  fi

  local name_pool=$(echo "$data" | cut -d'|' -f1)
  local personality=$(echo "$data" | cut -d'|' -f2)
  local specialties=$(echo "$data" | cut -d'|' -f3)
  local expertise_raw=$(echo "$data" | cut -d'|' -f4-)

  # 이름 결정
  local name="${custom_name}"
  if [ -z "$name" ]; then
    name=$(_pick_name "$name_pool")
  fi
  local lower_name=$(echo "$name" | tr '[:upper:]' '[:lower:]')

  # 이미 존재하는지 확인
  if [ -f "${GOLEM_ROOT}/souls/${lower_name}.md" ]; then
    echo "[forge-soul] ERROR: ${name} SOUL이 이미 존재합니다."
    return 1
  fi

  # 모델 결정 (role 기반 기본값)
  local model="$custom_model"
  case "$role" in
    security-auditor) [ "$custom_model" = "sonnet" ] && model="opus" ;;
    qa-tester|technical-writer) [ "$custom_model" = "sonnet" ] && model="haiku" ;;
  esac

  local date=$(date +%Y-%m-%d)

  # expertise를 줄바꿈으로 분리
  local expertise_lines=""
  local IFS='|'
  local count=0
  for item in $expertise_raw; do
    if [ $count -lt 3 ]; then
      expertise_lines="${expertise_lines}
- ${item}"
    else
      # 나머지는 행동 원칙
      break
    fi
    count=$((count + 1))
  done

  local principles_lines=""
  count=0
  for item in $expertise_raw; do
    if [ $count -ge 3 ]; then
      principles_lines="${principles_lines}
- ${item}"
    fi
    count=$((count + 1))
  done

  # SOUL 파일 생성
  cat > "${GOLEM_ROOT}/souls/${lower_name}.md" <<SOUL
---
name: ${name}
role: ${role}
rank: novice
specialty: [${specialties}]
personality: ${personality} (사용자 메모용, 프롬프트 미주입)
model: ${model}
created: ${date}
---

## 프로젝트 컨텍스트 (프롬프트에 주입됨)
- 역할: ${role}
- 기술스택: (프로젝트 초기화 시 설정)
- 아키텍처: (프로젝트 초기화 시 설정)
- 우선순위: (프로젝트 초기화 시 설정)

## 전문 지식 (컨텍스트 힌트로 주입)
${expertise_lines}

## 행동 원칙
${principles_lines}

## 성장 기록 요약
- ${date}: 생성 (Novice)
SOUL

  # growth-log 초기화
  echo "{\"date\":\"${date}\",\"task\":\"forge-soul-create\",\"result\":\"success\",\"files_changed\":0,\"tests_passed\":0}" > "${GOLEM_ROOT}/growth-log/${lower_name}.jsonl"

  echo "[forge-soul] ${name} (${role}) 생성 완료!"
  echo "  파일: souls/${lower_name}.md"
  echo "  모델: ${model}"
  echo "  랭크: novice"
  echo "  specialty: ${specialties}"
}

# 커스텀 SOUL 직접 생성 (비대화형, 파라미터 기반)
soul_create_custom() {
  local name="$1"
  local role="$2"
  local specialties="$3"
  local personality="${4:-}"
  local model="${5:-sonnet}"

  local lower_name=$(echo "$name" | tr '[:upper:]' '[:lower:]')
  local date=$(date +%Y-%m-%d)

  if [ -f "${GOLEM_ROOT}/souls/${lower_name}.md" ]; then
    echo "[forge-soul] ERROR: ${name} SOUL이 이미 존재합니다."
    return 1
  fi

  cat > "${GOLEM_ROOT}/souls/${lower_name}.md" <<SOUL
---
name: ${name}
role: ${role}
rank: novice
specialty: [${specialties}]
personality: ${personality} (사용자 메모용, 프롬프트 미주입)
model: ${model}
created: ${date}
---

## 프로젝트 컨텍스트 (프롬프트에 주입됨)
- 역할: ${role}
- 기술스택: (프로젝트 초기화 시 설정)
- 아키텍처: (프로젝트 초기화 시 설정)
- 우선순위: (프로젝트 초기화 시 설정)

## 전문 지식 (컨텍스트 힌트로 주입)
- (프로젝트에 맞게 추가)

## 행동 원칙
- (프로젝트에 맞게 추가)

## 성장 기록 요약
- ${date}: 생성 (Novice)
SOUL

  echo "{\"date\":\"${date}\",\"task\":\"forge-soul-create\",\"result\":\"success\",\"files_changed\":0,\"tests_passed\":0}" > "${GOLEM_ROOT}/growth-log/${lower_name}.jsonl"

  echo "[forge-soul] ${name} (${role}) 커스텀 생성 완료!"
  echo "  파일: souls/${lower_name}.md"
}

# 모든 프리셋 한번에 생성 (팀 빠른 구성용)
soul_create_all_presets() {
  echo "=== 전체 프리셋 SOUL 생성 ==="
  echo ""

  local roles="backend-developer frontend-developer devops-engineer qa-tester data-analyst technical-writer security-auditor"
  for role in $roles; do
    soul_create_from_preset "$role"
    echo ""
  done

  echo "=== 완료: $(ls "${GOLEM_ROOT}/souls/"*.md 2>/dev/null | wc -l | tr -d ' \r')개 SOUL 등록됨 ==="
}
