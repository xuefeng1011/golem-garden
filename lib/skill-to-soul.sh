#!/usr/bin/env bash
# skill-to-soul.sh — Agent Skill (agentskills.io) -> SOUL.md 역변환기
# Usage:
#   bash lib/skill-to-soul.sh path/to/golem-soul-ryn/ [output-dir]
#   bash lib/skill-to-soul.sh path/to/skills/ --all [output-dir]
#
# Agent Skill의 golem-* metadata가 있으면 원본 SOUL 필드 복원.
# 없으면 기본값 적용 (rank=novice, model=sonnet 등).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GOLEM_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GOLEM_DIR="${GOLEM_DIR:-${GOLEM_ROOT}}"
GOLEM_PROJECT="${GOLEM_PROJECT:-${GOLEM_ROOT}}"

# ── SKILL.md frontmatter 파서 ──

_skill_get_field() {
  local file="$1"
  local field="$2"
  sed -n '/^---$/,/^---$/p' "$file" | grep "^${field}:" | head -1 | sed "s/^${field}:[[:space:]]*//"
}

_skill_get_metadata() {
  local file="$1"
  local key="$2"
  # metadata 블록 내에서 키 추출
  sed -n '/^metadata:/,/^[^ ]/p' "$file" | grep "^  ${key}:" | head -1 | sed "s/^  ${key}:[[:space:]]*//" | tr -d '"'
}

_skill_get_body_section() {
  local file="$1"
  local section="$2"
  sed -n "/^## ${section}/,/^## /{ /^## ${section}/d; /^## /d; p; }" "$file" | sed '/^$/{ N; /^\n$/d; }'
}

# ── 역변환 메인 ──

skill_to_soul() {
  local skill_dir="$1"
  local output_dir="$2"

  local skill_md="${skill_dir}/SKILL.md"
  if [ ! -f "$skill_md" ]; then
    echo "[ERROR] SKILL.md not found in: $skill_dir" >&2
    return 1
  fi

  # golem-* metadata에서 복원 시도
  local g_role g_rank g_specialty g_maxTurns g_effort g_created g_soul_marker
  g_soul_marker=$(_skill_get_metadata "$skill_md" "golem-soul")
  g_role=$(_skill_get_metadata "$skill_md" "golem-role")
  g_rank=$(_skill_get_metadata "$skill_md" "golem-rank")
  g_specialty=$(_skill_get_metadata "$skill_md" "golem-specialty")
  g_maxTurns=$(_skill_get_metadata "$skill_md" "golem-maxTurns")
  g_effort=$(_skill_get_metadata "$skill_md" "golem-effort")
  g_created=$(_skill_get_metadata "$skill_md" "golem-created")

  # name 추출 (golem-soul- 접두사 제거)
  local skill_name
  skill_name=$(_skill_get_field "$skill_md" "name")
  local soul_name
  soul_name=$(echo "$skill_name" | sed 's/^golem-soul-//')
  # 첫 글자 대문자
  local soul_name_cap
  soul_name_cap=$(echo "$soul_name" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')

  # description -> personality (golem-* 없는 외부 스킬용)
  local description
  description=$(_skill_get_field "$skill_md" "description")
  # multiline description (> 접두사) 처리
  if [ -z "$description" ]; then
    description=$(sed -n '/^description:/,/^[a-z]/{/^description:/d; /^[a-z]/d; s/^  //; p;}' "$skill_md" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
  fi

  # allowed-tools -> tools 배열
  local allowed_tools
  allowed_tools=$(_skill_get_field "$skill_md" "allowed-tools")

  # 기본값 적용
  local role="${g_role:-backend-developer}"
  local rank="${g_rank:-novice}"
  local effort="${g_effort:-medium}"
  local created="${g_created:-$(date +%Y-%m-%d)}"
  local maxTurns="${g_maxTurns}"

  # specialty: golem-* 있으면 복원, 없으면 description에서 추출 시도
  local specialty_array=""
  if [ -n "$g_specialty" ]; then
    specialty_array="[$(echo "$g_specialty" | sed 's/,/, /g')]"
  else
    specialty_array="[general]"
  fi

  # tools: allowed-tools 있으면 변환, 없으면 rank 기반
  local tools_array=""
  if [ -n "$allowed_tools" ]; then
    tools_array="[$(echo "$allowed_tools" | sed 's/ /, /g')]"
  fi

  # maxTurns 기본값 (rank 기반)
  if [ -z "$maxTurns" ]; then
    case "$rank" in
      novice) maxTurns=15 ;; junior) maxTurns=25 ;; senior) maxTurns=40 ;;
      lead)   maxTurns=60 ;; master) maxTurns=80 ;; *) maxTurns=15 ;;
    esac
  fi

  # model 추론 (effort 기반)
  local model="sonnet"
  case "$effort" in
    low)  model="haiku" ;;
    high) model="opus" ;;
  esac

  # isolation 추론 (rank 기반)
  local isolation="none"
  case "$rank" in
    senior|lead|master) isolation="worktree" ;;
  esac
  # director는 항상 none
  [ "$role" = "director" ] && isolation="none"

  # personality
  local personality=""
  if [ -z "$g_soul_marker" ]; then
    # 외부 스킬 — description을 personality로
    personality="$description"
  fi

  # ── SOUL.md 작성 ──
  mkdir -p "$output_dir"
  local out_file="${output_dir}/${soul_name}.md"

  {
    echo "---"
    echo "name: ${soul_name_cap}"
    echo "role: ${role}"
    echo "rank: ${rank}"
    echo "specialty: ${specialty_array}"
    if [ -n "$personality" ]; then
      echo "personality: ${personality}"
    fi
    echo "model: ${model}"
    if [ -n "$tools_array" ]; then
      echo "tools: ${tools_array}"
    fi
    echo "maxTurns: ${maxTurns}"
    echo "isolation: ${isolation}"
    echo "effort: ${effort}"
    echo "created: ${created}"
    echo "---"
    echo ""
  } > "$out_file"

  # body sections 복원
  local ctx knowledge principles growth

  ctx=$(_skill_get_body_section "$skill_md" "Project Context")
  if [ -n "$ctx" ]; then
    printf "## 프로젝트 컨텍스트 (프롬프트에 주입됨)\n%s\n\n" "$ctx" >> "$out_file"
  else
    printf "## 프로젝트 컨텍스트 (프롬프트에 주입됨)\n- 역할: %s\n- 기술스택: (프로젝트 초기화 시 설정)\n- 우선순위: > 안정성 > 테스트 > 성능\n\n" "$role" >> "$out_file"
  fi

  knowledge=$(_skill_get_body_section "$skill_md" "Domain Knowledge")
  if [ -n "$knowledge" ]; then
    printf "## 전문 지식 (컨텍스트 힌트로 주입)\n%s\n\n" "$knowledge" >> "$out_file"
  else
    printf "## 전문 지식 (컨텍스트 힌트로 주입)\n- (임포트된 스킬 — 전문 지식 추가 필요)\n\n" >> "$out_file"
  fi

  principles=$(_skill_get_body_section "$skill_md" "Behavioral Principles")
  if [ -n "$principles" ]; then
    printf "## 행동 원칙\n%s\n\n" "$principles" >> "$out_file"
  else
    printf "## 행동 원칙\n- 정확성 우선\n- 테스트 가능한 코드 작성\n\n" >> "$out_file"
  fi

  growth=$(_skill_get_body_section "$skill_md" "Growth Summary")
  if [ -n "$growth" ]; then
    printf "## 성장 기록 요약\n%s\n" "$growth" >> "$out_file"
  else
    printf "## 성장 기록 요약\n- %s: Agent Skill에서 임포트 (%s)\n" "$(date +%Y-%m-%d)" "$rank" >> "$out_file"
  fi

  # references/ 에서 memory 복원
  local ref_memory="${skill_dir}/references/memory.md"
  if [ -f "$ref_memory" ] && grep -q "^\- \*\*" "$ref_memory" 2>/dev/null; then
    mkdir -p "${GOLEM_DIR}/memory"
    local mem_out="${GOLEM_DIR}/memory/${soul_name}.jsonl"
    grep "^\- \*\*" "$ref_memory" | while IFS= read -r line; do
      local task lesson tags
      task=$(echo "$line" | sed 's/^- \*\*\([^*]*\)\*\*.*/\1/')
      lesson=$(echo "$line" | sed 's/^- \*\*[^*]*\*\*: \(.*\) (`[^`]*`)$/\1/')
      tags=$(echo "$line" | sed 's/.*`\([^`]*\)`).*/\1/')
      printf '{"date":"%s","task":"%s","lesson":"%s","tags":"%s"}\n' \
        "$(date +%Y-%m-%d)" "$task" "$lesson" "$tags" >> "$mem_out"
    done
    echo "  [+] Memory restored: ${mem_out}"
  fi

  local is_golem=""
  [ -n "$g_soul_marker" ] && is_golem=" (GolemGarden 원본 복원)"
  echo "[OK] ${skill_name} -> ${out_file}${is_golem}"
}

# ── CLI ──

usage() {
  echo "Usage:"
  echo "  $0 <skill-dir> [output-dir]           Import one Agent Skill"
  echo "  $0 <parent-dir> --all [output-dir]     Import all Agent Skills"
  echo ""
  echo "Default output-dir: .golem/souls/"
}

skill_to_soul_main() {
  local target="${1:-}"
  local second="${2:-}"
  local output_dir

  if [ -z "$target" ]; then
    usage
    exit 1
  fi

  if [ "$second" = "--all" ]; then
    output_dir="${3:-${GOLEM_DIR}/souls}"
    local count=0
    for skill_dir in "${target}"/*/; do
      [ -f "${skill_dir}/SKILL.md" ] || continue
      skill_to_soul "$skill_dir" "$output_dir"
      count=$((count + 1))
    done
    echo ""
    echo "[DONE] Imported ${count} Agent Skills to ${output_dir}/"
  else
    output_dir="${second:-${GOLEM_DIR}/souls}"
    if [ -f "${target}/SKILL.md" ]; then
      skill_to_soul "$target" "$output_dir"
    else
      echo "[ERROR] Not a valid Agent Skill directory: $target" >&2
      echo "  Expected: ${target}/SKILL.md"
      exit 1
    fi
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  skill_to_soul_main "$@"
fi
