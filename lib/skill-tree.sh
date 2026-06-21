#!/usr/bin/env bash
# skill-tree.sh — SOUL 전문화 분기 시스템
# Senior 승급 시 전문화 브랜치를 선택하여 역량 집중
# Usage: source lib/skill-tree.sh && skill_tree_branches backend-developer

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${GOLEM_ROOT}/lib/soul-parser.sh"

# 전문화 데이터 파일
SKILL_TREE_FILE="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/skill-trees.jsonl"

# ─────────────────────────────────────────────────────────
# 역할별 전문화 브랜치 정의
# ─────────────────────────────────────────────────────────

# 역할별 사용 가능한 브랜치 목록
# skill_tree_branches <role>
skill_tree_branches() {
  local role="$1"
  case "$role" in
    backend-developer)
      echo "performance:쿼리 최적화, 캐싱, 프로파일링, 부하 테스트"
      echo "security:인증/인가, OWASP, 취약점 점검, 암호화"
      echo "architecture:MSA 설계, DDD, 이벤트 소싱, CQRS"
      ;;
    frontend-developer)
      echo "performance:번들 최적화, 렌더링 성능, 메모리 관리"
      echo "accessibility:WCAG, 스크린 리더, 키보드 네비게이션"
      echo "animation:모션 디자인, 전환 효과, Canvas/WebGL"
      ;;
    devops-engineer)
      echo "reliability:SRE, 카오스 엔지니어링, 장애 복구"
      echo "security:DevSecOps, 컨테이너 보안, 네트워크 정책"
      echo "cost:클라우드 비용 최적화, 스팟 인스턴스, 오토스케일링"
      ;;
    qa-tester)
      echo "automation:E2E 자동화, 시각적 회귀, CI 통합"
      echo "performance:부하 테스트, 스트레스 테스트, 병목 분석"
      echo "security:침투 테스트, 퍼징, 보안 스캔"
      ;;
    game-logic-developer)
      echo "physics:물리 엔진, 충돌 최적화, 래그돌"
      echo "ai:게임 AI, 행동 트리, 경로 탐색"
      echo "networking:멀티플레이어, 네트코드, 동기화"
      ;;
    data-analyst)
      echo "ml:머신러닝, 피처 엔지니어링, 모델 평가"
      echo "visualization:대시보드, 인터랙티브 차트, 스토리텔링"
      echo "pipeline:ETL, 스트리밍, 데이터 품질"
      ;;
    director)
      echo "strategy:장기 로드맵, 기술 부채 관리, 우선순위 설정"
      echo "people:팀 성장, 멘토링, 코드 리뷰 문화"
      echo "process:CI/CD 파이프라인, 배포 전략, 모니터링"
      ;;
    *)
      echo "generalist:범용 역량 강화"
      ;;
  esac
}

# 전문화 선택 (Senior 승급 시)
# skill_tree_specialize <soul_name> <branch_name>
skill_tree_specialize() {
  local soul_name="$1"
  local branch="$2"

  local soul_file=$(_resolve_soul_file "$soul_name")
  [ ! -f "$soul_file" ] && { echo "[skill-tree] ERROR: SOUL 없음: $soul_name"; return 1; }

  soul_parse "$soul_file"

  # Senior 이상만 전문화 가능
  case "$SOUL_RANK" in
    novice|junior)
      echo "[skill-tree] ${soul_name}: Senior 이상만 전문화 가능 (현재: ${SOUL_RANK})"
      return 1
      ;;
  esac

  # 이미 전문화되어 있는지 확인
  if [ -f "$SKILL_TREE_FILE" ] && grep -q "\"soul\":\"${soul_name}\"" "$SKILL_TREE_FILE" 2>/dev/null; then
    local existing=$(grep "\"soul\":\"${soul_name}\"" "$SKILL_TREE_FILE" | tail -1 | grep -o '"branch":"[^"]*"' | sed 's/"branch":"//;s/"//')
    echo "[skill-tree] ${soul_name}: 이미 '${existing}' 전문화됨"
    echo "[skill-tree] 변경하려면 forge skill-tree respec ${soul_name} ${branch}"
    return 1
  fi

  # 브랜치 유효성 확인
  local branches=$(skill_tree_branches "$SOUL_ROLE")
  local branch_detail=""
  while IFS= read -r line; do
    local b_name=$(echo "$line" | cut -d: -f1)
    if [ "$b_name" = "$branch" ]; then
      branch_detail=$(echo "$line" | cut -d: -f2)
      break
    fi
  done <<< "$branches"

  if [ -z "$branch_detail" ]; then
    echo "[skill-tree] ERROR: '${branch}'는 ${SOUL_ROLE}의 유효한 브랜치가 아닙니다"
    echo "[skill-tree] 사용 가능한 브랜치:"
    echo "$branches" | while IFS= read -r line; do
      echo "  - $(echo "$line" | cut -d: -f1): $(echo "$line" | cut -d: -f2)"
    done
    return 1
  fi

  mkdir -p "$(dirname "$SKILL_TREE_FILE")"

  # 전문화 기록
  local date=$(date +%Y-%m-%d)
  echo "{\"date\":\"${date}\",\"soul\":\"${soul_name}\",\"role\":\"${SOUL_ROLE}\",\"branch\":\"${branch}\",\"detail\":\"${branch_detail}\"}" >> "$SKILL_TREE_FILE"

  echo "[skill-tree] ${soul_name}: '${branch}' 전문화 완료!"
  echo "  전문 영역: ${branch_detail}"
  echo ""
  echo "  효과:"
  echo "  - 전문 지식 섹션에 '${branch}' 관련 지식 자동 주입"
  echo "  - 해당 분야 태스크에 우선 배정"
  echo "  - 프롬프트에 전문화 컨텍스트 추가"
}

# 전문화 변경 (리스펙)
skill_tree_respec() {
  local soul_name="$1"
  local new_branch="$2"

  if [ -f "$SKILL_TREE_FILE" ]; then
    # 기존 전문화 제거
    grep -v "\"soul\":\"${soul_name}\"" "$SKILL_TREE_FILE" > "${SKILL_TREE_FILE}.tmp" 2>/dev/null || true
    mv "${SKILL_TREE_FILE}.tmp" "$SKILL_TREE_FILE"
  fi

  echo "[skill-tree] ${soul_name}: 전문화 초기화"
  skill_tree_specialize "$soul_name" "$new_branch"
}

# SOUL의 현재 전문화 조회
# skill_tree_current <soul_name>
# 반환: "branch:detail" 또는 빈 문자열
skill_tree_current() {
  local soul_name="$1"

  if [ ! -f "$SKILL_TREE_FILE" ]; then
    echo ""
    return
  fi

  local entry=$(grep "\"soul\":\"${soul_name}\"" "$SKILL_TREE_FILE" 2>/dev/null | tail -1)
  if [ -z "$entry" ]; then
    echo ""
    return
  fi

  local branch=$(echo "$entry" | grep -o '"branch":"[^"]*"' | sed 's/"branch":"//;s/"//')
  local detail=$(echo "$entry" | grep -o '"detail":"[^"]*"' | sed 's/"detail":"//;s/"//')
  echo "${branch}:${detail}"
}

# 프롬프트 주입용 전문화 블록
# skill_tree_prompt_block <soul_name>
skill_tree_prompt_block() {
  local soul_name="$1"
  local current=$(skill_tree_current "$soul_name")

  [ -z "$current" ] && return

  local branch=$(echo "$current" | cut -d: -f1)
  local detail=$(echo "$current" | cut -d: -f2-)

  cat <<STBLOCK

[전문화: ${branch}]
이 SOUL은 '${branch}' 분야에 전문화되어 있습니다.
전문 영역: ${detail}
이 분야의 베스트 프랙티스와 깊은 지식을 활용하여 작업하세요.
STBLOCK
}

# 전문화 대시보드
skill_tree_dashboard() {
  echo "=== GolemGarden Skill Tree Dashboard ==="
  echo ""

  printf "%-10s %-22s %-14s %s\n" "SOUL" "Role" "Branch" "Specialization"
  printf "%-10s %-22s %-14s %s\n" "----" "----" "------" "--------------"

  while IFS= read -r soul_file; do
    [ -f "$soul_file" ] || continue
    soul_parse "$soul_file"
    local current=$(skill_tree_current "$SOUL_NAME")
    local branch="—"
    local detail="(미전문화)"
    if [ -n "$current" ]; then
      branch=$(echo "$current" | cut -d: -f1)
      detail=$(echo "$current" | cut -d: -f2- | cut -c1-35)
    fi

    # Senior 이상만 전문화 가능 표시
    case "$SOUL_RANK" in
      novice|junior) detail="(${SOUL_RANK} — Senior 이후 가능)" ;;
    esac

    printf "%-10s %-22s %-14s %s\n" "$SOUL_NAME" "$SOUL_ROLE" "$branch" "$detail"
  done < <(_all_soul_files)
}
