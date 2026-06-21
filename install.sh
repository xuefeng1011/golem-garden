#!/usr/bin/env bash
# GolemGarden Installer — OMC 위에 설치
# 사전 조건: oh-my-claudecode가 설치되어 있어야 함

set -e

GOLEM_HOME="$HOME/.claude/golem-garden"
SKILLS_HOME="$HOME/.claude/skills/golem-garden"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --with-bats 플래그: bats-core 벤더링 확인 및 설치 안내
WITH_BATS=0
for arg in "$@"; do
  [[ "$arg" == "--with-bats" ]] && WITH_BATS=1
done

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
echo "[1/6] 디렉토리 생성..."
mkdir -p "$GOLEM_HOME/souls"
mkdir -p "$GOLEM_HOME/growth-log"
mkdir -p "$GOLEM_HOME/lib"
mkdir -p "$GOLEM_HOME/domain-packs"
mkdir -p "$GOLEM_HOME/templates"
mkdir -p "$SKILLS_HOME/forge-init"
mkdir -p "$SKILLS_HOME/forge-team"
mkdir -p "$SKILLS_HOME/forge-review"
mkdir -p "$SKILLS_HOME/forge-sync"
mkdir -p "$SKILLS_HOME/forge-soul"
mkdir -p "$GOLEM_HOME/.claude/hooks"

# 3. SOUL 파일 복사 (글로벌 원본만, .golem/은 제외)
echo "[2/5] SOUL 템플릿 설치..."
cp -r "$SCRIPT_DIR/souls/"* "$GOLEM_HOME/souls/" 2>/dev/null || true
cp -r "$SCRIPT_DIR/templates/"* "$GOLEM_HOME/templates/" 2>/dev/null || true

# 4. 라이브러리 + forge.sh + 도메인팩 복사
echo "[3/5] 라이브러리 설치..."
cp "$SCRIPT_DIR/forge.sh" "$GOLEM_HOME/forge.sh"
cp "$SCRIPT_DIR/lib/"*.sh "$GOLEM_HOME/lib/" 2>/dev/null || true
cp -r "$SCRIPT_DIR/domain-packs/"* "$GOLEM_HOME/domain-packs/" 2>/dev/null || true

# 4.5. CRLF → LF 정규화 (Git for Windows bash compatibility)
echo "[3.5/6] Line ending 정규화 (CRLF → LF)..."
if command -v tr &>/dev/null; then
  while IFS= read -r -d '' f; do
    tr -d '\r' < "$f" > "${f}.lf" && mv "${f}.lf" "$f"
  done < <(find "$GOLEM_HOME" -type f -name "*.sh" -print0)
  echo "  완료: $GOLEM_HOME 내 .sh 파일 CRLF 정규화"
fi

# 5. 스킬 파일 복사
echo "[4/6] 스킬 설치..."
cp "$SCRIPT_DIR/skills/golem-garden/SKILL.md" "$SKILLS_HOME/SKILL.md"
cp "$SCRIPT_DIR/skills/golem-garden/forge-init/SKILL.md" "$SKILLS_HOME/forge-init/SKILL.md"
cp "$SCRIPT_DIR/skills/golem-garden/forge-team/SKILL.md" "$SKILLS_HOME/forge-team/SKILL.md"
cp "$SCRIPT_DIR/skills/golem-garden/forge-review/SKILL.md" "$SKILLS_HOME/forge-review/SKILL.md"
cp "$SCRIPT_DIR/skills/golem-garden/forge-sync/SKILL.md" "$SKILLS_HOME/forge-sync/SKILL.md" 2>/dev/null || true
cp "$SCRIPT_DIR/skills/golem-garden/forge-soul/SKILL.md" "$SKILLS_HOME/forge-soul/SKILL.md" 2>/dev/null || true

# 5.5. Hook 파일 복사
echo "[5/6] Hook 설치..."
if [ -d "$SCRIPT_DIR/.claude/hooks" ]; then
  cp "$SCRIPT_DIR/.claude/hooks/"*.sh "$GOLEM_HOME/.claude/hooks/" 2>/dev/null || true
fi

# 5.6. 글로벌 Stop hook 등록 (모든 프로젝트에서 대시보드 자동 갱신)
GLOBAL_SETTINGS="$HOME/.claude/settings.json"
if [ -f "$GLOBAL_SETTINGS" ]; then
  HOOK_CMD="bash \$HOME/.claude/golem-garden/.claude/hooks/auto-dashboard-refresh.sh"
  if ! grep -q "auto-dashboard-refresh" "$GLOBAL_SETTINGS" 2>/dev/null; then
    echo "  글로벌 Stop hook 등록이 필요합니다."
    echo "  ~/.claude/settings.json에 다음을 추가하세요:"
    echo "  hooks.Stop: $HOOK_CMD"
  else
    echo "  글로벌 Stop hook: 이미 등록됨"
  fi
fi

# 5.7. 글로벌 CLAUDE.md에 GolemGarden 규칙 등록
GLOBAL_CLAUDE="$HOME/.claude/CLAUDE.md"
GOLEM_MARKER="<!-- GOLEM:START -->"
GOLEM_END_MARKER="<!-- GOLEM:END -->"

if [ -f "$GLOBAL_CLAUDE" ]; then
  if grep -q "$GOLEM_MARKER" "$GLOBAL_CLAUDE" 2>/dev/null; then
    # 기존 블록 제거 (awk로 GOLEM:START~GOLEM:END 사이 + 후행 빈줄 제거)
    # END 마커 미발견 시 에러 종료하여 내용 손실 방지
    CLAUDE_TMP=$(mktemp "${GLOBAL_CLAUDE}.XXXXXX")
    awk -v start="$GOLEM_MARKER" -v end="$GOLEM_END_MARKER" '
      $0 ~ start { skip=1; next }
      $0 ~ end   { skip=0; skip_blank=1; next }
      skip_blank && /^[[:space:]]*$/ { skip_blank=0; next }
      !skip { skip_blank=0; print }
      END { if (skip) { print "ERROR: GOLEM:END not found" > "/dev/stderr"; exit 1 } }
    ' "$GLOBAL_CLAUDE" > "$CLAUDE_TMP"
    if [ $? -eq 0 ]; then
      mv "$CLAUDE_TMP" "$GLOBAL_CLAUDE"
    else
      rm -f "$CLAUDE_TMP"
      echo "  [ERROR] GOLEM 블록 손상 — 기존 블록 유지, 새 블록 추가 건너뜀"
    fi
  fi
  # 블록 추가 (파일 끝에)
  if ! grep -q "$GOLEM_MARKER" "$GLOBAL_CLAUDE" 2>/dev/null; then
    cat >> "$GLOBAL_CLAUDE" <<'GOLEMEOF'

<!-- GOLEM:START -->
# GolemGarden — 글로벌 규칙

<golem_rules_critical>
**1. forge 스킬 강제 호출**
사용자 입력에 "forge", "포지", "forje" 또는 SOUL 이름 + 태스크가 포함되면
반드시 Skill 도구로 `golem-garden` 스킬을 호출하라.
직접 forge.sh를 실행하거나, 스킬 없이 작업을 수행하는 것은 금지한다.
이 규칙은 어떤 상황에서도 우회할 수 없다.

**2. SOUL 실행 가시성 (누가 뭘 하는지 표시)**
SOUL을 Agent로 소환할 때 반드시 아래 형식으로 사용자에게 먼저 표시하라:
```
──────────────────────────────────
>> {SOUL_NAME} ({role}) 작업 시작
   태스크: {task_summary}
   모델: {model} | 랭크: {rank} | 도구: {tools}
──────────────────────────────────
```
Agent 호출 전에 이 메시지를 출력해야 한다. 생략 금지.
병렬 실행 시 각 SOUL마다 개별 표시한다.
완료 시에도 결과를 SOUL별로 표시한다:
```
<< {SOUL_NAME} 완료 — {result} ({files}파일, {tests}테스트)
```

**3. 보호 대상 직접 수정 금지**
아래 파일은 절대 Edit/Write로 직접 수정하지 않는다:
- SOUL 파일: `souls/*.md`, `.golem/souls/*.md` → `forge soul-create` 사용
- 성장 기록: `growth-log/*.jsonl`, `.golem/growth-log/*.jsonl` → `forge log-add` 사용
- 메일박스: `.golem/mailbox/*.jsonl` → `forge mailbox` 명령 사용
- 업적/케미: `achievements.jsonl`, `chemistry.jsonl` → forge 명령 사용
</golem_rules_critical>

<golem_rules>
- 모든 `forge.sh` 호출 시 반드시 `GOLEM_PROJECT="$(pwd)"` 환경변수를 전달하라
- SOUL 파일(`souls/*.md`)은 직접 Edit/Write 하지 마라 — `forge soul-create` 또는 `forge-init`을 사용
- growth-log(`growth-log/*.jsonl`)은 직접 수정하지 마라 — `forge.sh log-add`로만 기록
- mailbox(`mailbox/*.jsonl`)은 직접 수정하지 마라 — `forge mailbox` 명령 사용
</golem_rules>
<!-- GOLEM:END -->
GOLEMEOF
    echo "  글로벌 CLAUDE.md: GolemGarden 규칙 등록 완료"
  else
    echo "  글로벌 CLAUDE.md: GolemGarden 규칙 이미 등록됨"
  fi
else
  echo "  [WARN] ~/.claude/CLAUDE.md 없음 — GolemGarden 규칙 미등록"
fi

# 6. growth-log 초기화
echo "[6/6] Growth log 초기화..."
for soul_file in "$GOLEM_HOME/souls/"*.md; do
  [ -f "$soul_file" ] || continue
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
echo "  글로벌:  $GOLEM_HOME/"
echo "  스킬:    $SKILLS_HOME/"
echo ""
echo "글로벌 구조:"
echo "  $GOLEM_HOME/"
echo "  ├── forge.sh          CLI 진입점"
echo "  ├── souls/             SOUL 원본 (tools/maxTurns/isolation/effort 포함)"
echo "  ├── lib/               라이브러리 ($(ls "$GOLEM_HOME/lib/"*.sh 2>/dev/null | wc -l | tr -d ' ')개 모듈)"
echo "  │   ├── soul-parser, growth-log, rank-system, prompt-builder"
echo "  │   ├── mailbox, session, error-recovery, worktree"
echo "  │   ├── budget, tool-character (비용/도구 성격)"
echo "  │   ├── soul-memory, retrospective, chemistry (성장)"
echo "  │   ├── achievement, skill-tree, project-dna (차별화)"
echo "  │   └── dashboard-web, dashboard-global (대시보드)"
echo "  ├── templates/         템플릿"
echo "  ├── domain-packs/      도메인 팩"
echo "  ├── .claude/hooks/     Hook 스크립트"
echo "  └── growth-log/        글로벌 성장 기록 (비용 추적 포함)"
echo ""
echo "프로젝트별 (.golem/)은 forge-init 시 자동 생성됩니다."
echo ""
echo "시작하기:"
echo "  Claude Code에서: forge-init"
echo "  CLI에서: bash $GOLEM_HOME/forge.sh status"
echo ""

# --with-bats: bats-core 벤더링 상태 확인
if [[ "$WITH_BATS" -eq 1 ]]; then
  BATS_DIR="$SCRIPT_DIR/tests/bats/bats-core"
  echo "=== bats-core 확인 (--with-bats) ==="
  if [[ -x "$BATS_DIR/bin/bats" ]]; then
    BATS_VER=$("$BATS_DIR/bin/bats" --version 2>/dev/null || echo "unknown")
    echo "  bats-core: $BATS_VER (벤더링 OK)"
    echo "  실행: bash tests/bats/run.sh"
  else
    echo "  [INFO] bats-core가 벤더링되어 있지 않습니다."
    echo "  아래 명령으로 설치하세요:"
    echo ""
    echo "    curl -fsSL https://github.com/bats-core/bats-core/archive/refs/tags/v1.11.0.tar.gz \\"
    echo "      -o /tmp/bats.tar.gz"
    echo "    tar -xzf /tmp/bats.tar.gz -C tests/bats/"
    echo "    mv tests/bats/bats-core-1.11.0 tests/bats/bats-core"
    echo "    rm /tmp/bats.tar.gz"
  fi
  echo ""
fi
