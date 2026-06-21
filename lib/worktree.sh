#!/usr/bin/env bash
# worktree.sh — Git Worktree 기반 SOUL 격리 시스템
# Usage: source lib/worktree.sh && forge_worktree_create ryn "인증 API"

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${GOLEM_ROOT}/lib/soul-parser.sh"

# Worktree 디렉토리 (프로젝트 .golem/ 아래)
WORKTREE_DIR="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/worktrees"

# Git 저장소 확인
_worktree_check_git() {
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "[worktree] ERROR: git 저장소가 아닙니다"
    return 1
  fi
  return 0
}

# Worktree 생성 (SOUL별 격리된 작업 공간)
# forge_worktree_create <soul_name> [task_description]
forge_worktree_create() {
  local soul_name="$1"
  soul_name=$(basename "$soul_name")
  if [[ "$soul_name" =~ [^a-zA-Z0-9_-] ]]; then
    echo "[worktree] ERROR: 잘못된 SOUL 이름: $soul_name" >&2
    return 1
  fi
  local task="${2:-work}"

  _worktree_check_git || return 1

  mkdir -p "$WORKTREE_DIR"

  # 브랜치 이름 생성 (soul-이름-타임스탬프)
  local branch="golem-${soul_name}-$(date +%s)"
  local worktree_path="${WORKTREE_DIR}/${soul_name}"

  # 이미 존재하는 worktree 확인
  if [ -d "$worktree_path" ]; then
    echo "[worktree] ${soul_name}: 이미 존재합니다 (${worktree_path})"
    echo "[worktree] 기존 worktree를 사용하거나 forge worktree cleanup ${soul_name}으로 정리하세요"
    return 1
  fi

  # Worktree 생성
  git worktree add "$worktree_path" -b "$branch" 2>&1
  local status=$?

  if [ $status -ne 0 ]; then
    echo "[worktree] ERROR: worktree 생성 실패 (exit=${status})"
    return 1
  fi

  echo "[worktree] ${soul_name}: 생성 완료"
  echo "  경로: ${worktree_path}"
  echo "  브랜치: ${branch}"
  echo "  태스크: ${task}"

  # 메타 정보 저장
  echo "{\"soul\":\"${soul_name}\",\"branch\":\"${branch}\",\"task\":\"${task}\",\"created\":\"$(date -u +%Y-%m-%dT%H:%M:%S 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)\",\"status\":\"active\"}" > "${worktree_path}/.golem-worktree.json"

  echo "$worktree_path"
}

# Worktree 변경사항을 메인 브랜치에 머지
# forge_worktree_merge <soul_name> [merge_strategy]
# merge_strategy: merge (기본) | squash | rebase
forge_worktree_merge() {
  local soul_name="$1"
  local strategy="${2:-merge}"
  local worktree_path="${WORKTREE_DIR}/${soul_name}"

  _worktree_check_git || return 1

  if [ ! -d "$worktree_path" ]; then
    echo "[worktree] ERROR: ${soul_name} worktree 없음"
    return 1
  fi

  # 메타 정보에서 브랜치 읽기
  local meta_file="${worktree_path}/.golem-worktree.json"
  local branch=""
  if [ -f "$meta_file" ]; then
    branch=$(grep -o '"branch":"[^"]*"' "$meta_file" | sed 's/"branch":"//;s/"//')
  fi

  if [ -z "$branch" ]; then
    echo "[worktree] ERROR: 브랜치 정보를 찾을 수 없음"
    return 1
  fi

  # worktree에 변경사항이 있는지 확인
  local changes=$(cd "$worktree_path" && git diff --name-only 2>/dev/null | wc -l | tr -d ' \r')
  local staged=$(cd "$worktree_path" && git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' \r')
  local committed=$(git log main.."$branch" --oneline 2>/dev/null | wc -l | tr -d ' \r')

  if [ "$changes" -eq 0 ] && [ "$staged" -eq 0 ] && [ "$committed" -eq 0 ]; then
    echo "[worktree] ${soul_name}: 변경사항 없음 — 자동 정리"
    forge_worktree_cleanup "$soul_name"
    return 0
  fi

  # worktree에서 커밋되지 않은 변경사항이 있으면 먼저 커밋
  if [ "$changes" -gt 0 ] || [ "$staged" -gt 0 ]; then
    (cd "$worktree_path" && git add -A && git commit -m "feat(${soul_name}): worktree 작업 완료" 2>&1)
  fi

  # 메인 브랜치에서 머지
  local main_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")

  case "$strategy" in
    squash)
      echo "[worktree] ${soul_name}: squash merge (${branch} → ${main_branch})"
      git merge --squash "$branch" 2>&1
      git commit -m "feat(${soul_name}): $(grep -o '"task":"[^"]*"' "$meta_file" | sed 's/"task":"//;s/"//')" 2>&1
      ;;
    rebase)
      echo "[worktree] ${soul_name}: rebase merge (${branch} → ${main_branch})"
      git rebase "$branch" 2>&1
      ;;
    *)
      echo "[worktree] ${soul_name}: merge (${branch} → ${main_branch})"
      git merge "$branch" --no-edit 2>&1
      ;;
  esac

  local merge_status=$?
  if [ $merge_status -ne 0 ]; then
    echo "[worktree] WARNING: 머지 충돌 발생. 수동 해결 필요"
    echo "[worktree] 충돌 해결 후 forge worktree cleanup ${soul_name}으로 정리하세요"
    return 1
  fi

  echo "[worktree] ${soul_name}: 머지 완료"

  # 머지 후 자동 정리
  forge_worktree_cleanup "$soul_name"
  return 0
}

# Worktree 정리 (삭제)
# forge_worktree_cleanup <soul_name|all>
forge_worktree_cleanup() {
  local target="$1"

  _worktree_check_git || return 1

  if [ "$target" = "all" ]; then
    echo "[worktree] 전체 worktree 정리..."
    for wt_path in "${WORKTREE_DIR}"/*/; do
      [ -d "$wt_path" ] || continue
      local name=$(basename "$wt_path")
      _worktree_remove "$name"
    done
    # worktrees 디렉토리 자체 정리
    [ -d "$WORKTREE_DIR" ] && rmdir "$WORKTREE_DIR" 2>/dev/null
    echo "[worktree] 전체 정리 완료"
    return 0
  fi

  _worktree_remove "$target"
}

# 내부: 단일 worktree 제거
_worktree_remove() {
  local soul_name="$1"
  local worktree_path="${WORKTREE_DIR}/${soul_name}"

  if [ ! -d "$worktree_path" ]; then
    echo "[worktree] ${soul_name}: worktree 없음 (이미 정리됨)"
    return 0
  fi

  # 메타에서 브랜치 정보
  local meta_file="${worktree_path}/.golem-worktree.json"
  local branch=""
  if [ -f "$meta_file" ]; then
    branch=$(grep -o '"branch":"[^"]*"' "$meta_file" | sed 's/"branch":"//;s/"//')
  fi

  # worktree 제거
  git worktree remove "$worktree_path" --force 2>&1 || rm -rf "$worktree_path"

  # 브랜치 삭제
  if [ -n "$branch" ]; then
    git branch -D "$branch" 2>/dev/null
  fi

  echo "[worktree] ${soul_name}: 정리 완료"
}

# Worktree 상태 대시보드
forge_worktree_status() {
  _worktree_check_git || return 1

  echo "=== GolemGarden Worktree Status ==="
  echo ""

  # git worktree list 결과
  local wt_list=$(git worktree list 2>/dev/null)
  local wt_count=$(echo "$wt_list" | wc -l | tr -d ' \r')

  if [ ! -d "$WORKTREE_DIR" ] || [ -z "$(ls -A "$WORKTREE_DIR" 2>/dev/null)" ]; then
    echo "  활성 worktree 없음"
    echo ""
    echo "  생성: forge worktree create <soul_name> [task]"
    return 0
  fi

  printf "%-10s %-30s %-12s %-10s %s\n" "SOUL" "Branch" "Status" "Changes" "Task"
  printf "%-10s %-30s %-12s %-10s %s\n" "----" "------" "------" "-------" "----"

  for wt_path in "${WORKTREE_DIR}"/*/; do
    [ -d "$wt_path" ] || continue
    local name=$(basename "$wt_path")
    local meta_file="${wt_path}/.golem-worktree.json"

    local branch="—"
    local task="—"
    local status="active"
    if [ -f "$meta_file" ]; then
      branch=$(grep -o '"branch":"[^"]*"' "$meta_file" | sed 's/"branch":"//;s/"//')
      task=$(grep -o '"task":"[^"]*"' "$meta_file" | sed 's/"task":"//;s/"//' | cut -c1-30)
      status=$(grep -o '"status":"[^"]*"' "$meta_file" | sed 's/"status":"//;s/"//')
    fi

    # 변경 파일 수
    local changes=$(cd "$wt_path" && git diff --name-only 2>/dev/null | wc -l | tr -d ' \r')
    local committed=$(git log main.."$branch" --oneline 2>/dev/null | wc -l | tr -d ' \r')
    local change_str="${changes}개 수정, ${committed}개 커밋"

    printf "%-10s %-30s %-12s %-10s %s\n" "$name" "$branch" "$status" "$change_str" "$task"
  done
}

# SOUL의 isolation 설정에 따라 자동으로 worktree 생성 여부 결정
# forge_worktree_auto <soul_name> <task>
# 반환값: worktree 경로 (isolation=worktree일 때) 또는 빈 문자열 (none일 때)
forge_worktree_auto() {
  local soul_name="$1"
  local task="$2"

  local soul_file=$(_resolve_soul_file "$soul_name")
  if [ ! -f "$soul_file" ]; then
    echo ""
    return
  fi

  soul_parse "$soul_file"
  local isolation="${SOUL_ISOLATION:-none}"

  if [ "$isolation" = "worktree" ]; then
    local wt_path=$(forge_worktree_create "$soul_name" "$task" 2>/dev/null | grep "^/" | head -1)
    if [ -n "$wt_path" ]; then
      echo "$wt_path"
    else
      # worktree 생성 실패 시 (git 없음 등) 빈 문자열 반환
      echo ""
    fi
  else
    echo ""
  fi
}
