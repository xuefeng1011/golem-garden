#!/bin/bash
# handover-scan.sh — 프로젝트 자동 분석 스캐너 (handover M1 MVP)
# Usage: bash lib/handover-scan.sh <project_root> <output_src_dir>
# Output: <output_src_dir>/00-overview.md ~ 07-people.md (8 files)
#
# 규칙:
#   - set -euo pipefail
#   - sed -i 금지 → 임시파일 + mv 사용
#   - 모든 변수 "$VAR" 쿼팅
#   - local 변수 의무
#   - tree 명령 의존 금지 → find 기반 디렉토리 트리

set -euo pipefail

# ── 인자 검증 ─────────────────────────────────────────────
if [ "$#" -lt 2 ]; then
  echo "[ERROR] Usage: bash lib/handover-scan.sh <project_root> <output_src_dir>" >&2
  exit 1
fi

PROJECT_ROOT="$(cd "$1" 2>/dev/null && pwd)" || {
  echo "[ERROR] project_root 경로를 찾을 수 없습니다: $1" >&2
  exit 1
}
OUTPUT_DIR="$2"

# ── 출력 디렉토리 생성 ────────────────────────────────────
mkdir -p "$OUTPUT_DIR"

# ── 공통 배지 ─────────────────────────────────────────────
BADGE='> 🤖 자동 분석 — 검토 필요. M2 인터뷰에서 보강 예정.'
PLACEHOLDER_INTERVIEW='_(자동 분석으로 추출되지 않음 — 인터뷰에서 채워질 영역)_'
NOT_FOUND='_(없음)_'
NOT_EXTRACTED='_(자동 분석으로 추출되지 않음)_'

# ── 유틸: 파일 앞 N줄 읽기 ────────────────────────────────
_head_n() {
  local file="$1"
  local n="$2"
  if [ -f "$file" ]; then
    head -n "$n" "$file" 2>/dev/null || true
  fi
}

# ── 유틸: 문자열이 비면 기본값 반환 ──────────────────────
_or_default() {
  local val="$1"
  local default="$2"
  if [ -z "$val" ]; then
    printf '%s' "$default"
  else
    printf '%s' "$val"
  fi
}

# ── 00-overview.md ────────────────────────────────────────
write_overview() {
  local out="$OUTPUT_DIR/00-overview.md"
  local project_name
  project_name="$(basename "$PROJECT_ROOT")"

  {
    echo "# 프로젝트 개요 / Project Overview"
    echo ""
    echo "$BADGE"
    echo ""
    echo "## 프로젝트 이름 / Project Name"
    echo ""
    echo "\`$project_name\`"
    echo ""
    echo "## README 요약 / README Summary"
    echo ""
    local readme=""
    for f in README.md README.rst README.txt readme.md; do
      if [ -f "$PROJECT_ROOT/$f" ]; then
        readme="$PROJECT_ROOT/$f"
        break
      fi
    done
    if [ -n "$readme" ]; then
      echo "_(파일: \`$(basename "$readme")\`)_"
      echo ""
      echo '```'
      _head_n "$readme" 30
      echo '```'
    else
      echo "$NOT_FOUND"
    fi
    echo ""

    echo "## CLAUDE.md / AGENTS.md 요약"
    echo ""
    local found_meta=0
    for f in CLAUDE.md AGENTS.md .claude/CLAUDE.md; do
      if [ -f "$PROJECT_ROOT/$f" ]; then
        echo "### \`$f\`"
        echo ""
        echo '```'
        _head_n "$PROJECT_ROOT/$f" 20
        echo '```'
        echo ""
        found_meta=1
      fi
    done
    if [ "$found_meta" -eq 0 ]; then
      echo "$NOT_FOUND"
    fi
  } > "$out"
  echo "[OK] $out"
}

# ── 01-architecture.md ───────────────────────────────────
write_architecture() {
  local out="$OUTPUT_DIR/01-architecture.md"
  {
    echo "# 아키텍처 / Architecture"
    echo ""
    echo "$BADGE"
    echo ""
    echo "## 엔트리 포인트 / Entry Points"
    echo ""

    local entry_files=()
    # 검색 대상 패턴
    local patterns=(
      "main.py" "main.ts" "main.js" "main.go" "main.rs" "main.rb" "main.java"
      "index.ts" "index.js" "index.py"
      "app.py" "app.ts" "app.js"
      "manage.py"
      "forge.sh"
    )
    for pat in "${patterns[@]}"; do
      while IFS= read -r f; do
        entry_files+=("$f")
      done < <(find "$PROJECT_ROOT" -maxdepth 3 \
        -not -path "*/node_modules/*" \
        -not -path "*/.venv/*" \
        -not -path "*/.git/*" \
        -not -path "*/dist/*" \
        -not -path "*/__pycache__/*" \
        -name "$pat" 2>/dev/null | sort)
    done

    # package.json main 필드
    local pkg="$PROJECT_ROOT/package.json"
    if [ -f "$pkg" ]; then
      local pkg_main
      pkg_main="$(grep '"main"' "$pkg" 2>/dev/null | head -1 | sed 's/.*"main"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)"
      if [ -n "$pkg_main" ]; then
        entry_files+=("package.json main → $pkg_main")
      fi
    fi

    if [ "${#entry_files[@]}" -gt 0 ]; then
      for ef in "${entry_files[@]}"; do
        # project_root 기준 상대 경로로 표시
        local rel
        rel="${ef#$PROJECT_ROOT/}"
        echo "- \`$rel\`"
      done
    else
      echo "$NOT_EXTRACTED"
    fi

    echo ""
    echo "## 의존성 카운트 / Dependency Count"
    echo ""

    # package.json dependencies
    if [ -f "$PROJECT_ROOT/package.json" ]; then
      local dep_count
      dep_count="$(grep -c '"version"' "$PROJECT_ROOT/package.json" 2>/dev/null || echo 0)"
      # 더 정확하게: dependencies + devDependencies 블록 내 항목 수
      local npm_deps
      npm_deps="$(grep -E '^\s+"[^"]+"\s*:\s*"[^"]+"' "$PROJECT_ROOT/package.json" 2>/dev/null | wc -l | tr -d ' ' || echo '?')"
      echo "- npm (\`package.json\`): 약 **${npm_deps}** 항목"
    fi

    # requirements*.txt
    while IFS= read -r req; do
      local cnt
      cnt="$(grep -cE '^[^#[:space:]][^=<>!]*' "$req" 2>/dev/null || echo 0)"
      local rrel="${req#$PROJECT_ROOT/}"
      echo "- pip (\`$rrel\`): **${cnt}** 패키지"
    done < <(find "$PROJECT_ROOT" -maxdepth 2 -name "requirements*.txt" 2>/dev/null | sort)

    # pyproject.toml
    if [ -f "$PROJECT_ROOT/pyproject.toml" ]; then
      local py_cnt
      py_cnt="$(grep -cE '^\s*"[^"]+[><=!]' "$PROJECT_ROOT/pyproject.toml" 2>/dev/null || echo '?')"
      echo "- pyproject.toml: 약 **${py_cnt}** 항목"
    fi

    echo ""
    echo "## 다이어그램 / Diagram"
    echo ""
    echo '```mermaid'
    echo '%%  M3에서 다이어그램 추가 예정'
    echo 'graph TD'
    echo '    A[Entry Point] --> B[Core Logic]'
    echo '    B --> C[...]'
    echo '```'
    echo ""
    echo "> _⚠️ 위 mermaid 다이어그램은 placeholder입니다. M3에서 자동 생성 예정._"
  } > "$out"
  echo "[OK] $out"
}

# ── 02-directory.md ──────────────────────────────────────
write_directory() {
  local out="$OUTPUT_DIR/02-directory.md"
  {
    echo "# 디렉토리 구조 / Directory Structure"
    echo ""
    echo "$BADGE"
    echo ""
    echo "## 최상위 트리 (3-depth) / Top-level Tree (depth 3)"
    echo ""
    echo "> _node_modules, .venv, .git, dist, \\_\\_pycache\\_\\_ 제외_"
    echo ""
    echo '```'

    # find 기반 3-depth 트리 (tree 명령 불필요)
    # 최상위 기준 상대 경로를 들여쓰기로 표시
    find "$PROJECT_ROOT" \
      -not -path "*/node_modules/*" \
      -not -path "*/.venv/*" \
      -not -path "*/.git/*" \
      -not -path "*/dist/*" \
      -not -path "*/__pycache__/*" \
      -not -path "*/.omc/*" \
      -mindepth 1 -maxdepth 3 \
      2>/dev/null \
      | sort \
      | while IFS= read -r path; do
          local rel="${path#$PROJECT_ROOT/}"
          # depth 계산 (슬래시 수)
          local depth
          depth="$(printf '%s' "$rel" | tr -cd '/' | wc -c)"
          local indent=""
          local i=0
          while [ "$i" -lt "$depth" ]; do
            indent="${indent}    "
            i=$((i + 1))
          done
          local name
          name="$(basename "$path")"
          if [ -d "$path" ]; then
            printf '%s%s/\n' "$indent" "$name"
          else
            printf '%s%s\n' "$indent" "$name"
          fi
        done

    echo '```'
    echo ""
    echo "## 디렉토리 요약 / Directory Summary"
    echo ""
    echo "| 경로 | README 첫 줄 요약 |"
    echo "|------|-----------------|"

    # 최상위 디렉토리들의 README 첫 줄
    find "$PROJECT_ROOT" -maxdepth 1 -mindepth 1 -type d \
      -not -name "node_modules" \
      -not -name ".venv" \
      -not -name ".git" \
      -not -name "dist" \
      -not -name "__pycache__" \
      2>/dev/null \
      | sort \
      | while IFS= read -r dir; do
          local dname
          dname="$(basename "$dir")"
          local summary="—"
          for rf in "$dir/README.md" "$dir/README.rst" "$dir/README.txt"; do
            if [ -f "$rf" ]; then
              summary="$(head -1 "$rf" 2>/dev/null | sed 's/^#\+[[:space:]]*//' | cut -c1-80 || echo '—')"
              break
            fi
          done
          printf '| `%s` | %s |\n' "$dname" "$summary"
        done
  } > "$out"
  echo "[OK] $out"
}

# ── 03-dev-guide.md ──────────────────────────────────────
write_dev_guide() {
  local out="$OUTPUT_DIR/03-dev-guide.md"
  {
    echo "# 개발 환경 가이드 / Dev Guide"
    echo ""
    echo "$BADGE"
    echo ""
    echo "## 의존성 파일 / Dependency Files"
    echo ""

    local found_any=0

    # package.json
    if [ -f "$PROJECT_ROOT/package.json" ]; then
      found_any=1
      echo "### \`package.json\`"
      echo ""
      echo '```json'
      # dependencies + devDependencies 섹션만 추출 (간략)
      python3 -c "
import json, sys
try:
    with open('$PROJECT_ROOT/package.json') as f:
        d = json.load(f)
    out = {}
    for k in ('dependencies', 'devDependencies', 'peerDependencies'):
        if k in d:
            out[k] = d[k]
    json.dump(out, sys.stdout, ensure_ascii=False, indent=2)
except Exception as e:
    print('(파싱 실패: ' + str(e) + ')')
" 2>/dev/null || _head_n "$PROJECT_ROOT/package.json" 50
      echo ""
      echo '```'
      echo ""
    fi

    # requirements*.txt
    while IFS= read -r req; do
      found_any=1
      local rrel="${req#$PROJECT_ROOT/}"
      echo "### \`$rrel\`"
      echo ""
      echo '```'
      grep -v '^#' "$req" 2>/dev/null | grep -v '^[[:space:]]*$' || true
      echo '```'
      echo ""
    done < <(find "$PROJECT_ROOT" -maxdepth 3 -name "requirements*.txt" 2>/dev/null | sort)

    # pyproject.toml
    if [ -f "$PROJECT_ROOT/pyproject.toml" ]; then
      found_any=1
      echo "### \`pyproject.toml\`"
      echo ""
      echo '```toml'
      _head_n "$PROJECT_ROOT/pyproject.toml" 60
      echo '```'
      echo ""
    fi

    # Cargo.toml
    if [ -f "$PROJECT_ROOT/Cargo.toml" ]; then
      found_any=1
      echo "### \`Cargo.toml\`"
      echo ""
      echo '```toml'
      _head_n "$PROJECT_ROOT/Cargo.toml" 40
      echo '```'
      echo ""
    fi

    # pom.xml
    if [ -f "$PROJECT_ROOT/pom.xml" ]; then
      found_any=1
      echo "### \`pom.xml\` (첫 40줄)"
      echo ""
      echo '```xml'
      _head_n "$PROJECT_ROOT/pom.xml" 40
      echo '```'
      echo ""
    fi

    # Gemfile
    if [ -f "$PROJECT_ROOT/Gemfile" ]; then
      found_any=1
      echo "### \`Gemfile\`"
      echo ""
      echo '```ruby'
      _head_n "$PROJECT_ROOT/Gemfile" 30
      echo '```'
      echo ""
    fi

    if [ "$found_any" -eq 0 ]; then
      echo "$NOT_FOUND"
      echo ""
    fi

    echo "## 개발 환경 셋업 명령 후보 / Setup Commands"
    echo ""
    echo "| 파일 감지 | 추천 명령 |"
    echo "|---------|---------|"

    [ -f "$PROJECT_ROOT/package.json" ] && echo "| package.json | \`npm install\` or \`pnpm install\` or \`yarn\` |"
    [ -f "$PROJECT_ROOT/package-lock.json" ] && echo "| package-lock.json | \`npm ci\` |"
    [ -f "$PROJECT_ROOT/yarn.lock" ] && echo "| yarn.lock | \`yarn install\` |"
    [ -f "$PROJECT_ROOT/pnpm-lock.yaml" ] && echo "| pnpm-lock.yaml | \`pnpm install\` |"
    [ -f "$PROJECT_ROOT/uv.lock" ] && echo "| uv.lock | \`uv sync\` |"
    [ -f "$PROJECT_ROOT/pyproject.toml" ] && echo "| pyproject.toml | \`uv sync\` or \`pip install -e .\` |"
    if find "$PROJECT_ROOT" -maxdepth 2 -name "requirements*.txt" 2>/dev/null | grep -q .; then
      echo "| requirements*.txt | \`pip install -r requirements.txt\` |"
    fi
    [ -f "$PROJECT_ROOT/Cargo.toml" ] && echo "| Cargo.toml | \`cargo build\` |"
    [ -f "$PROJECT_ROOT/pom.xml" ] && echo "| pom.xml | \`mvn install\` |"
    [ -f "$PROJECT_ROOT/Gemfile" ] && echo "| Gemfile | \`bundle install\` |"
    [ -f "$PROJECT_ROOT/go.mod" ] && echo "| go.mod | \`go mod tidy\` |"

    echo ""
    echo "## 빌드 / 실행 명령 후보 / Run Commands"
    echo ""

    # package.json scripts 추출
    if [ -f "$PROJECT_ROOT/package.json" ]; then
      echo "### npm scripts"
      echo ""
      echo '```'
      python3 -c "
import json, sys
try:
    with open('$PROJECT_ROOT/package.json') as f:
        d = json.load(f)
    scripts = d.get('scripts', {})
    for k, v in list(scripts.items())[:15]:
        print(f'  npm run {k}  →  {v}')
except Exception as e:
    print('(스크립트 추출 실패: ' + str(e) + ')')
" 2>/dev/null || echo "(추출 실패)"
      echo '```'
      echo ""
    fi

    # Makefile 타겟
    if [ -f "$PROJECT_ROOT/Makefile" ]; then
      echo "### Makefile targets"
      echo ""
      echo '```'
      grep -E '^[a-zA-Z0-9_-]+:' "$PROJECT_ROOT/Makefile" 2>/dev/null | head -20 | sed 's/:.*//' | while read -r t; do
        echo "  make $t"
      done || echo "(추출 실패)"
      echo '```'
      echo ""
    fi
  } > "$out"
  echo "[OK] $out"
}

# ── 04-pitfalls.md ───────────────────────────────────────
write_pitfalls() {
  local out="$OUTPUT_DIR/04-pitfalls.md"
  {
    echo "# 함정 & 주의사항 / Pitfalls & Gotchas"
    echo ""
    echo "$BADGE"
    echo ""
    echo "_⚠️ 인터뷰(Phase B, M2)에서 채워질 영역. 코드만으로는 추출 불가._"
    echo ""
    echo "## 예상 항목 (M2 인터뷰 대상)"
    echo ""
    echo "- 로컬 환경 설정 함정 (OS별 차이, 버전 충돌 등)"
    echo "- 자주 발생하는 빌드/런타임 오류"
    echo "- 코드베이스 관례 (암묵적 규칙)"
    echo "- 테스트 격리 주의사항"
    echo "- 배포 전 필수 체크리스트"
  } > "$out"
  echo "[OK] $out"
}

# ── 05-checklist.md ──────────────────────────────────────
write_checklist() {
  local out="$OUTPUT_DIR/05-checklist.md"
  {
    echo "# 온보딩 체크리스트 / Onboarding Checklist"
    echo ""
    echo "$BADGE"
    echo ""
    echo "## Day 1"
    echo ""
    echo "- [ ] 레포 클론 (Clone repository)"
    echo "- [ ] 개발 환경 셋업 (Environment setup — \`03-dev-guide.md\` 참고)"
    echo "- [ ] README 정독 (Read README)"
    echo "- [ ] 첫 빌드 성공 (First successful build)"
    echo "- [ ] 첫 테스트 실행 (Run test suite)"
    echo ""
    echo "## Week 1"
    echo ""
    echo "- [ ] 아키텍처 다이어그램 정독 (\`01-architecture.md\` 참고)"
    echo "- [ ] 디렉토리 5분 산책 (\`02-directory.md\` 참고)"
    echo "- [ ] 작은 PR 1건 — 버그 수정, 문서 개선, 타이포 수정 등"
    echo "- [ ] 팀 커뮤니케이션 채널 합류"
    echo "- [ ] 코드 리뷰 1건 참여"
    echo ""
    echo "## Month 1"
    echo ""
    echo "- [ ] 핵심 기능 1개 직접 구현"
    echo "- [ ] \`07-people.md\` 주요 기여자와 1:1 미팅"
    echo "- [ ] 온보딩 문서 개선 기여 (이 파일도 포함)"
  } > "$out"
  echo "[OK] $out"
}

# ── 06-glossary.md ───────────────────────────────────────
write_glossary() {
  local out="$OUTPUT_DIR/06-glossary.md"
  {
    echo "# 용어 사전 / Glossary"
    echo ""
    echo "$BADGE"
    echo ""
    echo "_📖 인터뷰(Phase B, M2)에서 채워질 영역._"
    echo ""
    echo "## 예상 항목 (M2 인터뷰 대상)"
    echo ""
    echo "- 프로젝트 고유 약어 / 코드명"
    echo "- 도메인 용어 정의"
    echo "- 팀 내부 은어 / 컨벤션 명칭"
    echo "- 외부 서비스 / 시스템 명칭"
  } > "$out"
  echo "[OK] $out"
}

# ── 07-people.md ─────────────────────────────────────────
write_people() {
  local out="$OUTPUT_DIR/07-people.md"
  {
    echo "# 팀 / People"
    echo ""
    echo "$BADGE"
    echo ""
    echo "## 최근 12개월 주요 기여자 / Recent Contributors (12 months)"
    echo ""

    local git_ok=0
    if command -v git >/dev/null 2>&1 && [ -d "$PROJECT_ROOT/.git" ]; then
      local contrib
      contrib="$(git -C "$PROJECT_ROOT" log --since="12.months" --format="%aN" 2>/dev/null \
        | sort 2>/dev/null \
        | uniq -c 2>/dev/null \
        | sort -rn 2>/dev/null \
        | head -10 2>/dev/null || echo "")"
      if [ -n "$contrib" ]; then
        git_ok=1
        echo "| 커밋 수 | 기여자 |"
        echo "|--------|--------|"
        while IFS= read -r line; do
          local cnt
          cnt="$(printf '%s' "$line" | awk '{print $1}')"
          local name
          name="$(printf '%s' "$line" | sed 's/^[[:space:]]*[0-9][0-9]*[[:space:]]*//')"
          printf '| %s | %s |\n' "$cnt" "$name"
        done <<< "$contrib"
      fi
    fi

    if [ "$git_ok" -eq 0 ]; then
      echo "$NOT_EXTRACTED"
      echo ""
      echo "> git 명령 실패 또는 .git 디렉토리 없음"
    fi

    echo ""
    echo "## CODEOWNERS"
    echo ""
    local codeowners=""
    for f in CODEOWNERS .github/CODEOWNERS docs/CODEOWNERS; do
      if [ -f "$PROJECT_ROOT/$f" ]; then
        codeowners="$PROJECT_ROOT/$f"
        break
      fi
    done
    if [ -n "$codeowners" ]; then
      echo "_(파일: \`$(basename "$codeowners")\`)_"
      echo ""
      echo '```'
      cat "$codeowners" 2>/dev/null || echo "(읽기 실패)"
      echo '```'
    else
      echo "$NOT_FOUND"
    fi
  } > "$out"
  echo "[OK] $out"
}

# ── 메인 실행 ────────────────────────────────────────────
echo "[handover-scan] 프로젝트: $PROJECT_ROOT"
echo "[handover-scan] 출력 디렉토리: $OUTPUT_DIR"
echo ""

write_overview
write_architecture
write_directory
write_dev_guide
write_pitfalls
write_checklist
write_glossary
write_people

echo ""
echo "[handover-scan] 완료 — 8개 파일 생성됨 → $OUTPUT_DIR"
