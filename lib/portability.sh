#!/bin/bash
# portability.sh — SOUL 포터빌리티 (프로젝트 간 이동)
# Usage: source lib/portability.sh && soul_export ryn /path/to/other/project

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${GOLEM_ROOT}/lib/soul-parser.sh"
source "${GOLEM_ROOT}/lib/growth-log.sh"

# GROWTH_DIR 명시적 보장 (growth-log.sh source 순서 비의존)
GROWTH_DIR="${GROWTH_DIR:-${GOLEM_DIR:-${GOLEM_ROOT}}/growth-log}"

# SOUL을 다른 프로젝트로 내보내기
soul_export() {
  local soul_name="$1"
  local target_dir="$2"

  local soul_file="${GOLEM_ROOT}/souls/${soul_name}.md"
  local log_file="${GOLEM_ROOT}/growth-log/${soul_name}.jsonl"

  if [ ! -f "$soul_file" ]; then
    echo "[export] ERROR: SOUL 없음: ${soul_name}"
    return 1
  fi

  if [ ! -d "$target_dir" ]; then
    echo "[export] ERROR: 대상 디렉토리 없음: ${target_dir}"
    return 1
  fi

  # 대상에 golem-garden 구조 생성
  mkdir -p "${target_dir}/souls"
  mkdir -p "${target_dir}/growth-log"

  # SOUL 파일 복사
  cp "$soul_file" "${target_dir}/souls/${soul_name}.md"
  echo "[export] SOUL 복사: ${soul_name}.md → ${target_dir}/souls/"

  # growth-log 복사 (이력 보존)
  if [ -f "$log_file" ]; then
    cp "$log_file" "${target_dir}/growth-log/${soul_name}.jsonl"
    echo "[export] Growth log 복사: ${soul_name}.jsonl → ${target_dir}/growth-log/"
  fi

  # 내보내기 이벤트 기록 (원본)
  local date=$(date +%Y-%m-%d)
  echo "{\"date\":\"${date}\",\"task\":\"EXPORT\",\"result\":\"exported to ${target_dir}\",\"files_changed\":0,\"tests_passed\":0}" >> "$log_file"

  soul_parse "$soul_file"
  echo ""
  echo "[export] 완료: ${SOUL_NAME} (${SOUL_ROLE}, ${SOUL_RANK})"
  echo "  이력: $(wc -l < "$log_file" | tr -d ' \r')건 포함"
  echo "  대상: ${target_dir}"
}

# 다른 프로젝트에서 SOUL 가져오기
soul_import() {
  local source_dir="$1"
  local soul_name="$2"

  local source_soul="${source_dir}/souls/${soul_name}.md"
  local source_log="${source_dir}/growth-log/${soul_name}.jsonl"

  if [ ! -f "$source_soul" ]; then
    echo "[import] ERROR: 소스 SOUL 없음: ${source_soul}"
    return 1
  fi

  local target_soul="${GOLEM_ROOT}/souls/${soul_name}.md"
  local target_log="${GOLEM_ROOT}/growth-log/${soul_name}.jsonl"

  # 이미 존재하면 확인
  if [ -f "$target_soul" ]; then
    echo "[import] WARN: ${soul_name} SOUL이 이미 존재합니다."
    echo "  기존: $(soul_get_field "$target_soul" "rank")"
    echo "  가져올: $(soul_get_field "$source_soul" "rank")"
    echo ""

    # 랭크가 높은 쪽을 유지
    local existing_rank=$(soul_get_field "$target_soul" "rank")
    local incoming_rank=$(soul_get_field "$source_soul" "rank")
    local existing_idx=$(rank_index "$existing_rank" 2>/dev/null || echo 0)
    local incoming_idx=$(rank_index "$incoming_rank" 2>/dev/null || echo 0)

    if [ "$incoming_idx" -gt "$existing_idx" ]; then
      echo "[import] 가져올 SOUL의 랭크가 더 높음 → 덮어쓰기"
      cp "$source_soul" "$target_soul"
    else
      echo "[import] 기존 SOUL의 랭크가 더 높거나 같음 → SOUL 유지, 로그만 병합"
    fi
  else
    cp "$source_soul" "$target_soul"
    echo "[import] SOUL 복사: ${soul_name}.md"
  fi

  # growth-log 병합 (기존 + 새로운 항목 합치기, 중복 제거)
  if [ -f "$source_log" ]; then
    if [ -f "$target_log" ]; then
      # 두 로그를 합치고 날짜순 정렬, 중복 제거
      cat "$target_log" "$source_log" | sort -t'"' -k4 | uniq > "${target_log}.tmp"
      mv "${target_log}.tmp" "$target_log"
      echo "[import] Growth log 병합 완료"
    else
      cp "$source_log" "$target_log"
      echo "[import] Growth log 복사"
    fi
  fi

  # 가져오기 이벤트 기록
  local date=$(date +%Y-%m-%d)
  echo "{\"date\":\"${date}\",\"task\":\"IMPORT\",\"result\":\"imported from ${source_dir}\",\"files_changed\":0,\"tests_passed\":0}" >> "$target_log"

  echo ""
  echo "[import] 완료: ${soul_name}"
  echo "  이력: $(wc -l < "$target_log" | tr -d ' \r')건"
}

# SOUL 팩으로 내보내기 (전체 팀)
soul_export_pack() {
  local pack_name="$1"
  local target_dir="${2:-.}"
  local pack_dir="${target_dir}/soul-pack-${pack_name}"

  mkdir -p "${pack_dir}/souls"
  mkdir -p "${pack_dir}/growth-log"

  echo "=== SOUL Pack Export: ${pack_name} ==="

  local count=0
  for soul_file in "${GOLEM_ROOT}/souls/"*.md; do
    [ -f "$soul_file" ] || continue
    local name=$(basename "$soul_file" .md)

    cp "$soul_file" "${pack_dir}/souls/${name}.md"

    local log_file="${GOLEM_ROOT}/growth-log/${name}.jsonl"
    if [ -f "$log_file" ]; then
      cp "$log_file" "${pack_dir}/growth-log/${name}.jsonl"
    fi

    count=$((count + 1))
  done

  # 팩 메타데이터 생성
  local date=$(date +%Y-%m-%d)
  cat > "${pack_dir}/PACK.md" <<EOF
---
name: ${pack_name}
exported: ${date}
soul_count: ${count}
source: ${GOLEM_ROOT}
---

# Soul Pack: ${pack_name}

## 포함된 SOUL

EOF

  for soul_file in "${pack_dir}/souls/"*.md; do
    [ -f "$soul_file" ] || continue
    soul_parse "$soul_file"
    echo "- **${SOUL_NAME}** (${SOUL_ROLE}) — Rank: ${SOUL_RANK}, Model: ${SOUL_MODEL}" >> "${pack_dir}/PACK.md"
  done

  echo "[export-pack] ${count}개 SOUL 내보내기 완료 → ${pack_dir}"
}

# SOUL 팩 가져오기 (전체 팀)
soul_import_pack() {
  local pack_dir="$1"

  if [ ! -f "${pack_dir}/PACK.md" ]; then
    echo "[import-pack] ERROR: 유효한 Soul Pack이 아닙니다: ${pack_dir}"
    return 1
  fi

  echo "=== SOUL Pack Import ==="
  cat "${pack_dir}/PACK.md" | head -20
  echo ""

  local count=0
  for soul_file in "${pack_dir}/souls/"*.md; do
    [ -f "$soul_file" ] || continue
    local name=$(basename "$soul_file" .md)
    soul_import "$pack_dir" "$name"
    count=$((count + 1))
    echo ""
  done

  echo "[import-pack] ${count}개 SOUL 가져오기 완료"
}

# SOUL 목록 + 포터빌리티 상태
portability_status() {
  echo "=== GolemGarden Portability Status ==="
  echo ""
  printf "%-10s %-10s %-8s %-8s %s\n" "SOUL" "Rank" "Tasks" "Exports" "Last Move"
  printf "%-10s %-10s %-8s %-8s %s\n" "----" "----" "-----" "-------" "---------"

  for soul_file in "${GOLEM_ROOT}/souls/"*.md; do
    [ -f "$soul_file" ] || continue
    soul_parse "$soul_file"
    local name="$SOUL_NAME"
    local log_file="${GROWTH_DIR}/${name}.jsonl"

    local tasks=$(growth_log_task_count "$name")
    local exports=0
    local last_move="—"

    if [ -f "$log_file" ]; then
      exports=$(grep -c '"task":"EXPORT"\|"task":"IMPORT"' "$log_file" 2>/dev/null | tr -d '\r' || echo "0")
      last_move=$(grep '"task":"EXPORT"\|"task":"IMPORT"' "$log_file" 2>/dev/null | tail -1 | grep -o '"date":"[^"]*"' | sed 's/"date":"//;s/"//' || echo "—")
      [ -z "$last_move" ] && last_move="—"
    fi

    printf "%-10s %-10s %-8s %-8s %s\n" "$name" "$SOUL_RANK" "${tasks}건" "${exports}건" "$last_move"
  done
}
