#!/bin/bash
# soul-to-skill.sh — SOUL.md -> Agent Skills (agentskills.io) 변환기
# Usage:
#   bash lib/soul-to-skill.sh souls/ryn.md [output-dir]
#   bash lib/soul-to-skill.sh --all [output-dir]
#
# Output: agentskills.io 호환 디렉토리 구조
#   golem-soul-{name}/
#   ├── SKILL.md
#   └── references/
#       ├── growth-log.md
#       ├── achievements.md
#       └── memory.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GOLEM_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GOLEM_DIR="${GOLEM_DIR:-${GOLEM_ROOT}}"
GOLEM_PROJECT="${GOLEM_PROJECT:-${GOLEM_ROOT}}"

source "$SCRIPT_DIR/soul-parser.sh"

# ── helpers ──

_role_description() {
  case "$1" in
    director)              echo "Task orchestrator and team coordinator" ;;
    backend-developer)     echo "Backend developer" ;;
    frontend-developer)    echo "Frontend developer" ;;
    qa-tester)             echo "QA and testing specialist" ;;
    devops-engineer)       echo "DevOps and infrastructure engineer" ;;
    data-analyst)          echo "Data analyst" ;;
    technical-writer)      echo "Technical documentation writer" ;;
    security-auditor)      echo "Security review specialist" ;;
    knowledge-auditor)     echo "Knowledge quality auditor" ;;
    game-logic-developer)  echo "Game logic developer" ;;
    game-designer)         echo "Game designer" ;;
    *)                     echo "Software developer ($1)" ;;
  esac
}

_specialty_to_prose() {
  local specs="$1"
  # [a, b, c] -> "a, b, and c"
  specs=$(echo "$specs" | tr -d '[]' | sed 's/,\s*/, /g')
  local count
  count=$(echo "$specs" | tr ',' '\n' | wc -l | tr -d ' ')
  if [ "$count" -le 1 ]; then
    echo "$specs"
  elif [ "$count" -eq 2 ]; then
    echo "$specs" | sed 's/,\s*/ and /'
  else
    echo "$specs" | sed 's/,\([^,]*\)$/, and\1/'
  fi
}

_tools_to_allowed() {
  # [Read, Edit, Write] -> "Read Edit Write"
  echo "$1" | tr -d '[]' | sed 's/,\s*/ /g'
}

_extract_body_section() {
  local file="$1"
  local section="$2"
  # Extract content between ## section and next ## (or EOF)
  sed -n "/^## ${section}/,/^## /{ /^## ${section}/d; /^## /d; p; }" "$file" | sed '/^$/{ N; /^\n$/d; }'
}

# ── main export ──

soul_to_skill() {
  local soul_file="$1"
  local output_base="$2"

  if [ ! -f "$soul_file" ]; then
    echo "[ERROR] SOUL file not found: $soul_file" >&2
    return 1
  fi

  soul_parse "$soul_file"

  local name_lower
  name_lower=$(echo "$SOUL_NAME" | tr '[:upper:]' '[:lower:]')
  local skill_name="golem-soul-${name_lower}"
  local skill_dir="${output_base}/${skill_name}"

  # create directory structure
  mkdir -p "${skill_dir}/references"

  # generate description
  local role_desc
  role_desc=$(_role_description "$SOUL_ROLE")
  local specialty_prose
  specialty_prose=$(_specialty_to_prose "$SOUL_SPECIALTY")
  local description="${role_desc} specializing in ${specialty_prose}. Rank: ${SOUL_RANK}."

  # tools -> allowed-tools
  local allowed_tools
  allowed_tools=$(_tools_to_allowed "$SOUL_TOOLS")

  # model -> compatibility
  local compat="Requires Claude Code or compatible agent runtime."
  case "$SOUL_MODEL" in
    opus)   compat="Best with opus-tier model. ${compat}" ;;
    haiku)  compat="Optimized for haiku-tier model. ${compat}" ;;
  esac

  # ── write SKILL.md ──
  cat > "${skill_dir}/SKILL.md" << SKILLEOF
---
name: ${skill_name}
description: >
  ${description}
allowed-tools: ${allowed_tools}
compatibility: ${compat}
metadata:
  golem-soul: "true"
  golem-role: ${SOUL_ROLE}
  golem-rank: ${SOUL_RANK}
  golem-specialty: "$(echo "$SOUL_SPECIALTY" | tr -d '[] ' | sed 's/"/\\"/g')"
  golem-maxTurns: "${SOUL_MAX_TURNS}"
  golem-effort: ${SOUL_EFFORT}
  golem-created: "${SOUL_CREATED}"
---

SKILLEOF

  # inject body sections (Korean + English header fallback)
  local ctx
  ctx=$(_extract_body_section "$soul_file" "프로젝트 컨텍스트")
  [ -z "$ctx" ] && ctx=$(_extract_body_section "$soul_file" "Project Context")
  if [ -n "$ctx" ]; then
    printf "## Project Context\n\n%s\n\n" "$ctx" >> "${skill_dir}/SKILL.md"
  fi

  local knowledge
  knowledge=$(_extract_body_section "$soul_file" "전문 지식")
  [ -z "$knowledge" ] && knowledge=$(_extract_body_section "$soul_file" "Domain Knowledge")
  if [ -n "$knowledge" ]; then
    printf "## Domain Knowledge\n\n%s\n\n" "$knowledge" >> "${skill_dir}/SKILL.md"
  fi

  local principles
  principles=$(_extract_body_section "$soul_file" "행동 원칙")
  [ -z "$principles" ] && principles=$(_extract_body_section "$soul_file" "Behavioral Principles")
  if [ -n "$principles" ]; then
    printf "## Behavioral Principles\n\n%s\n\n" "$principles" >> "${skill_dir}/SKILL.md"
  fi

  local growth
  growth=$(_extract_body_section "$soul_file" "성장 기록 요약")
  [ -z "$growth" ] && growth=$(_extract_body_section "$soul_file" "Growth Summary")
  if [ -n "$growth" ]; then
    printf "## Growth Summary\n\n%s\n" "$growth" >> "${skill_dir}/SKILL.md"
  fi

  # ── write references/growth-log.md ──
  local growth_file=""
  if [ -f "${GOLEM_DIR}/growth-log/${name_lower}.jsonl" ]; then
    growth_file="${GOLEM_DIR}/growth-log/${name_lower}.jsonl"
  elif [ -f "${GOLEM_ROOT}/growth-log/${name_lower}.jsonl" ]; then
    growth_file="${GOLEM_ROOT}/growth-log/${name_lower}.jsonl"
  fi

  if [ -n "$growth_file" ] && [ -s "$growth_file" ]; then
    {
      echo "# Growth Log: ${SOUL_NAME}"
      echo ""
      echo "Task history exported from GolemGarden."
      echo ""
      echo "| Date | Task | Result | Files | Tests | Cost |"
      echo "|------|------|--------|-------|-------|------|"
      local date task result files tests cost
      while IFS= read -r line; do
        date=$(echo "$line" | sed -n 's/.*"date":"\([^"]*\)".*/\1/p')
        task=$(echo "$line" | sed -n 's/.*"task":"\([^"]*\)".*/\1/p')
        result=$(echo "$line" | sed -n 's/.*"result":"\([^"]*\)".*/\1/p')
        files=$(echo "$line" | sed -n 's/.*"files_changed":\([0-9]*\).*/\1/p')
        tests=$(echo "$line" | sed -n 's/.*"tests_passed":\([0-9]*\).*/\1/p')
        cost=$(echo "$line" | sed -n 's/.*"cost_usd":\([0-9.]*\).*/\1/p')
        [ -z "$date" ] && continue
        echo "| ${date:-?} | ${task:-?} | ${result:-?} | ${files:-0} | ${tests:-0} | \$${cost:-0} |"
      done < "$growth_file"
    } > "${skill_dir}/references/growth-log.md"
  else
    printf "# Growth Log: %s\n\nNo task history yet.\n" "${SOUL_NAME}" > "${skill_dir}/references/growth-log.md"
  fi

  # ── write references/achievements.md ──
  local ach_file="${GOLEM_DIR}/achievements.jsonl"
  [ ! -f "$ach_file" ] && ach_file="${GOLEM_ROOT}/achievements.jsonl"

  if [ -f "$ach_file" ] && grep -q "\"soul\":\"${name_lower}\"" "$ach_file" 2>/dev/null; then
    {
      echo "# Achievements: ${SOUL_NAME}"
      echo ""
      echo "| Date | Badge | Description |"
      echo "|------|-------|-------------|"
      grep "\"soul\":\"${name_lower}\"" "$ach_file" | while IFS= read -r line; do
        local date name desc
        date=$(echo "$line" | sed -n 's/.*"date":"\([^"]*\)".*/\1/p')
        name=$(echo "$line" | sed -n 's/.*"name":"\([^"]*\)".*/\1/p')
        desc=$(echo "$line" | sed -n 's/.*"desc":"\([^"]*\)".*/\1/p')
        [ -z "$date" ] && continue
        echo "| ${date} | ${name:-?} | ${desc:-?} |"
      done
    } > "${skill_dir}/references/achievements.md"
  else
    printf "# Achievements: %s\n\nNo achievements earned yet.\n" "${SOUL_NAME}" > "${skill_dir}/references/achievements.md"
  fi

  # ── write references/memory.md ──
  local mem_file="${GOLEM_DIR}/memory/${name_lower}.jsonl"
  [ ! -f "$mem_file" ] && mem_file="${GOLEM_ROOT}/memory/${name_lower}.jsonl"

  if [ -f "$mem_file" ] && [ -s "$mem_file" ]; then
    {
      echo "# Learned Lessons: ${SOUL_NAME}"
      echo ""
      echo "Episodic memory exported from GolemGarden."
      echo ""
      while IFS= read -r line; do
        local task lesson tags
        task=$(echo "$line" | sed 's/.*"task":"\([^"]*\)".*/\1/')
        lesson=$(echo "$line" | sed 's/.*"lesson":"\([^"]*\)".*/\1/')
        tags=$(echo "$line" | sed 's/.*"tags":"\([^"]*\)".*/\1/')
        echo "- **${task}**: ${lesson} (\`${tags}\`)"
      done < "$mem_file"
    } > "${skill_dir}/references/memory.md"
  else
    printf "# Learned Lessons: %s\n\nNo lessons recorded yet.\n" "${SOUL_NAME}" > "${skill_dir}/references/memory.md"
  fi

  echo "[OK] ${SOUL_NAME} -> ${skill_dir}/"
}

# ── CLI ──

usage() {
  echo "Usage:"
  echo "  $0 <soul-file.md> [output-dir]    Export one SOUL"
  echo "  $0 --all [output-dir]              Export all SOULs"
  echo ""
  echo "Default output-dir: ./dist/skills/"
}

soul_to_skill_main() {
  local target="${1:-}"
  local output_dir="${2:-${GOLEM_ROOT}/dist/skills}"

  if [ -z "$target" ]; then
    usage
    exit 1
  fi

  mkdir -p "$output_dir"

  if [ "$target" = "--all" ]; then
    local count=0
    while IFS= read -r soul_file; do
      [ -f "$soul_file" ] || continue
      soul_to_skill "$soul_file" "$output_dir"
      count=$((count + 1))
    done < <(_all_soul_files)
    echo ""
    echo "[DONE] Exported ${count} SOULs to ${output_dir}/"
  else
    local resolved
    resolved=$(_resolve_soul_file "$target")
    if [ -z "$resolved" ]; then
      echo "[ERROR] SOUL not found: $target" >&2
      exit 1
    fi
    soul_to_skill "$resolved" "$output_dir"
  fi
}

# run only if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  soul_to_skill_main "$@"
fi
