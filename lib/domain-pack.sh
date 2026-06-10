#!/bin/bash
# domain-pack.sh — 도메인 스킬 팩 관리
# Usage: source lib/domain-pack.sh && pack_install gamedev

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKS_DIR="${GOLEM_ROOT}/domain-packs"
source "${GOLEM_ROOT}/lib/soul-parser.sh"
source "${GOLEM_ROOT}/lib/growth-log.sh"

# 사용 가능한 팩 목록
pack_list() {
  echo "=== GolemGarden Domain Packs ==="
  echo ""

  if [ ! -d "$PACKS_DIR" ]; then
    echo "(도메인 팩 없음)"
    return
  fi

  printf "%-15s %-8s %-12s %s\n" "Pack" "SOULs" "Status" "Description"
  printf "%-15s %-8s %-12s %s\n" "----" "-----" "------" "-----------"

  for pack_dir in "${PACKS_DIR}"/*/; do
    [ -d "$pack_dir" ] || continue
    local pack_name=$(basename "$pack_dir")
    local soul_count=$(ls "${pack_dir}/souls/"*.md 2>/dev/null | wc -l | tr -d ' \r')

    # 설치 여부 확인 (souls/ 에 해당 팩의 SOUL이 있는지)
    local installed="not installed"
    if [ -d "${pack_dir}/souls" ]; then
      local first_soul=$(ls "${pack_dir}/souls/"*.md 2>/dev/null | head -1)
      if [ -n "$first_soul" ]; then
        local first_name=$(basename "$first_soul" .md)
        if [ -f "${GOLEM_ROOT}/souls/${first_name}.md" ]; then
          installed="installed"
        fi
      fi
    fi

    local desc=""
    case "$pack_name" in
      gamedev)   desc="게임 개발 (디자인+그래픽+로직)" ;;
      trading)   desc="주식/크립토 (TA+리스크+뉴스)" ;;
      fullstack) desc="풀스택 웹앱 (BE+FE+QA+DevOps)" ;;
      physical-ai) desc="피지컬 AI (임베디드+엣지AI+Go+로보틱스)" ;;
      *)         desc="커스텀 도메인 팩" ;;
    esac

    printf "%-15s %-8s %-12s %s\n" "$pack_name" "${soul_count}개" "$installed" "$desc"
  done
}

# 팩 설치 (SOULs + forge-board 복사)
pack_install() {
  local pack_name="$1"
  local pack_dir="${PACKS_DIR}/${pack_name}"

  if [ ! -d "$pack_dir" ]; then
    echo "[pack] ERROR: 팩 없음: ${pack_name}"
    echo "사용 가능한 팩:"
    ls -d "${PACKS_DIR}"/*/ 2>/dev/null | xargs -I{} basename {}
    return 1
  fi

  echo "=== Domain Pack Install: ${pack_name} ==="
  echo ""

  # SOULs 복사
  local soul_count=0
  if [ -d "${pack_dir}/souls" ]; then
    for soul_file in "${pack_dir}/souls/"*.md; do
      [ -f "$soul_file" ] || continue
      local name=$(basename "$soul_file" .md)

      if [ -f "${GOLEM_ROOT}/souls/${name}.md" ]; then
        echo "[pack] SKIP: ${name} (이미 존재)"
      else
        cp "$soul_file" "${GOLEM_ROOT}/souls/${name}.md"

        # growth-log 초기화
        local date=$(date +%Y-%m-%d)
        echo "{\"date\":\"${date}\",\"task\":\"pack-install-${pack_name}\",\"result\":\"success\",\"files_changed\":0,\"tests_passed\":0}" > "${GOLEM_ROOT}/growth-log/${name}.jsonl"

        soul_parse "${GOLEM_ROOT}/souls/${name}.md"
        echo "[pack] INSTALLED: ${SOUL_NAME} (${SOUL_ROLE}, ${SOUL_MODEL})"
      fi
      soul_count=$((soul_count + 1))
    done
  fi

  # forge-board 복사 (있으면)
  local board_file=$(ls "${pack_dir}"/forge-board-*.md 2>/dev/null | head -1)
  if [ -n "$board_file" ]; then
    local board_name=$(basename "$board_file")
    cp "$board_file" "${GOLEM_ROOT}/${board_name}"
    echo "[pack] BOARD: ${board_name} 설치됨"
  fi

  echo ""
  echo "[pack] ${pack_name} 설치 완료 (${soul_count}개 SOUL)"
  echo ""

  # 팀 상태 출력
  soul_list
}

# 팩 제거 (해당 팩의 SOUL만 제거)
pack_uninstall() {
  local pack_name="$1"
  local pack_dir="${PACKS_DIR}/${pack_name}"

  if [ ! -d "$pack_dir" ]; then
    echo "[pack] ERROR: 팩 없음: ${pack_name}"
    return 1
  fi

  echo "=== Domain Pack Uninstall: ${pack_name} ==="
  echo ""

  local removed=0
  if [ -d "${pack_dir}/souls" ]; then
    for soul_file in "${pack_dir}/souls/"*.md; do
      [ -f "$soul_file" ] || continue
      local name=$(basename "$soul_file" .md)

      if [ -f "${GOLEM_ROOT}/souls/${name}.md" ]; then
        rm "${GOLEM_ROOT}/souls/${name}.md"
        echo "[pack] REMOVED: ${name}.md"
        removed=$((removed + 1))
        # growth-log는 보존 (이력 유지)
      fi
    done
  fi

  # forge-board 제거
  local board_file=$(ls "${GOLEM_ROOT}"/forge-board-${pack_name}.md 2>/dev/null | head -1)
  if [ -n "$board_file" ]; then
    rm "$board_file"
    echo "[pack] BOARD: $(basename "$board_file") 제거됨"
  fi

  echo ""
  echo "[pack] ${pack_name} 제거 완료 (${removed}개 SOUL 제거, growth-log 보존)"
}

# 팩 상세 정보
pack_info() {
  local pack_name="$1"
  local pack_dir="${PACKS_DIR}/${pack_name}"

  if [ ! -d "$pack_dir" ]; then
    echo "[pack] ERROR: 팩 없음: ${pack_name}"
    return 1
  fi

  echo "=== Domain Pack: ${pack_name} ==="
  echo ""

  # SOULs 목록
  echo "SOULs:"
  printf "  %-10s %-22s %-8s %s\n" "Name" "Role" "Model" "Specialty"
  printf "  %-10s %-22s %-8s %s\n" "----" "----" "-----" "---------"

  for soul_file in "${pack_dir}/souls/"*.md; do
    [ -f "$soul_file" ] || continue
    soul_parse "$soul_file"
    printf "  %-10s %-22s %-8s %s\n" "$SOUL_NAME" "$SOUL_ROLE" "$SOUL_MODEL" "$SOUL_SPECIALTY"
  done

  # forge-board
  local board_file=$(ls "${pack_dir}"/forge-board-*.md 2>/dev/null | head -1)
  if [ -n "$board_file" ]; then
    echo ""
    echo "Forge Board: $(basename "$board_file")"
  fi

  # 스킬
  echo ""
  echo "Skills:"
  for skill_dir in "${pack_dir}/skills/"*/; do
    [ -d "$skill_dir" ] || continue
    echo "  - $(basename "$skill_dir")"
  done
}
