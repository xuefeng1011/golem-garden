#!/bin/bash
# GolemGarden Installer — OMC 위에 설치
# 사전 조건: oh-my-claudecode가 설치되어 있어야 함

set -e

GOLEM_HOME="$HOME/.claude/golem-garden"
SKILLS_HOME="$HOME/.claude/skills/golem-garden"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== GolemGarden Installer ==="
echo ""

# 1. OMC 설치 확인
if [ ! -d "$HOME/.claude/plugins" ] && [ ! -f "$HOME/.claude/settings.json" ]; then
  echo "[WARN] oh-my-claudecode가 감지되지 않았습니다."
  echo "  먼저 OMC를 설치하세요:"
  echo "  /plugin marketplace add https://github.com/Yeachan-Heo/oh-my-claudecode"
  echo ""
fi

# 2. 디렉토리 생성
echo "[1/4] 디렉토리 생성..."
mkdir -p "$GOLEM_HOME/souls"
mkdir -p "$GOLEM_HOME/growth-log"
mkdir -p "$SKILLS_HOME/forge-init"
mkdir -p "$SKILLS_HOME/forge-team"
mkdir -p "$SKILLS_HOME/forge-review"

# 3. SOUL 파일 복사
echo "[2/4] SOUL 템플릿 설치..."
cp -r "$SCRIPT_DIR/souls/"* "$GOLEM_HOME/souls/" 2>/dev/null || true
cp -r "$SCRIPT_DIR/templates/" "$GOLEM_HOME/templates/" 2>/dev/null || true

# 4. 스킬 파일 복사
echo "[3/4] 스킬 설치..."
cp "$SCRIPT_DIR/skills/golem-garden/SKILL.md" "$SKILLS_HOME/SKILL.md"
cp "$SCRIPT_DIR/skills/golem-garden/forge-init/SKILL.md" "$SKILLS_HOME/forge-init/SKILL.md"
cp "$SCRIPT_DIR/skills/golem-garden/forge-team/SKILL.md" "$SKILLS_HOME/forge-team/SKILL.md"
cp "$SCRIPT_DIR/skills/golem-garden/forge-review/SKILL.md" "$SKILLS_HOME/forge-review/SKILL.md"

# 5. growth-log 초기화
echo "[4/4] Growth log 초기화..."
for soul_file in "$GOLEM_HOME/souls/"*.md; do
  name=$(basename "$soul_file" .md)
  log_file="$GOLEM_HOME/growth-log/${name}.jsonl"
  if [ ! -f "$log_file" ]; then
    echo "{\"date\":\"$(date +%Y-%m-%d)\",\"task\":\"forge-init\",\"result\":\"success\",\"files_changed\":0,\"tests_passed\":0}" > "$log_file"
  fi
done

echo ""
echo "=== GolemGarden 설치 완료 ==="
echo ""
echo "설치 경로:"
echo "  SOUL:    $GOLEM_HOME/souls/"
echo "  스킬:    $SKILLS_HOME/"
echo "  로그:    $GOLEM_HOME/growth-log/"
echo ""
echo "시작하기:"
echo "  forge-init: {프로젝트 유형}, {기술스택}"
echo ""
