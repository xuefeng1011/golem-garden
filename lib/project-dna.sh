#!/bin/bash
# project-dna.sh — 프로젝트 지문(DNA) + SOUL 적응 시스템
# forge-init 시 프로젝트 DNA 생성, SOUL 이동 시 DNA 비교로 적응 자동 보정
# Usage: source lib/project-dna.sh && dna_generate

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${GOLEM_ROOT}/lib/soul-parser.sh"

# DNA 파일
DNA_FILE="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/project-dna.json"

# 프로젝트 DNA 생성 (forge-init 시 호출)
# dna_generate [languages] [frameworks] [architecture] [test_frameworks] [domain]
dna_generate() {
  local languages="${1:-}"
  local frameworks="${2:-}"
  local architecture="${3:-}"
  local test_frameworks="${4:-}"
  local domain="${5:-}"

  mkdir -p "$(dirname "$DNA_FILE")"

  # 자동 감지 (인자가 없으면)
  if [ -z "$languages" ]; then
    languages=$(_dna_detect_languages)
  fi
  if [ -z "$frameworks" ]; then
    frameworks=$(_dna_detect_frameworks)
  fi
  if [ -z "$test_frameworks" ]; then
    test_frameworks=$(_dna_detect_test_frameworks)
  fi

  local date=$(date +%Y-%m-%d)
  local project_name=$(basename "${GOLEM_PROJECT:-$(pwd)}")

  cat > "$DNA_FILE" <<DNAEOF
{"project":"${project_name}","date":"${date}","languages":"${languages}","frameworks":"${frameworks}","architecture":"${architecture}","test_frameworks":"${test_frameworks}","domain":"${domain}","complexity":"medium"}
DNAEOF

  echo "[dna] 프로젝트 DNA 생성: ${project_name}"
  echo "  언어: ${languages}"
  echo "  프레임워크: ${frameworks}"
  echo "  아키텍처: ${architecture}"
  echo "  테스트: ${test_frameworks}"
  echo "  도메인: ${domain}"
}

# 언어 자동 감지
_dna_detect_languages() {
  local langs=""
  local project_dir="${GOLEM_PROJECT:-$(pwd)}"

  [ -f "${project_dir}/pom.xml" ] || [ -f "${project_dir}/build.gradle" ] && langs="${langs},java"
  [ -f "${project_dir}/package.json" ] && langs="${langs},javascript"
  [ -f "${project_dir}/tsconfig.json" ] && langs="${langs},typescript"
  [ -f "${project_dir}/requirements.txt" ] || [ -f "${project_dir}/pyproject.toml" ] && langs="${langs},python"
  [ -f "${project_dir}/go.mod" ] && langs="${langs},go"
  [ -f "${project_dir}/Cargo.toml" ] && langs="${langs},rust"
  [ -f "${project_dir}/Gemfile" ] && langs="${langs},ruby"

  echo "$langs" | sed 's/^,//'
}

# 프레임워크 자동 감지
_dna_detect_frameworks() {
  local fws=""
  local project_dir="${GOLEM_PROJECT:-$(pwd)}"

  if [ -f "${project_dir}/pom.xml" ]; then
    grep -q "spring-boot" "${project_dir}/pom.xml" 2>/dev/null && fws="${fws},spring-boot"
  fi
  if [ -f "${project_dir}/package.json" ]; then
    grep -q '"react"' "${project_dir}/package.json" 2>/dev/null && fws="${fws},react"
    grep -q '"vue"' "${project_dir}/package.json" 2>/dev/null && fws="${fws},vue"
    grep -q '"next"' "${project_dir}/package.json" 2>/dev/null && fws="${fws},nextjs"
    grep -q '"express"' "${project_dir}/package.json" 2>/dev/null && fws="${fws},express"
  fi
  if [ -f "${project_dir}/requirements.txt" ]; then
    grep -qi "django" "${project_dir}/requirements.txt" 2>/dev/null && fws="${fws},django"
    grep -qi "flask" "${project_dir}/requirements.txt" 2>/dev/null && fws="${fws},flask"
    grep -qi "fastapi" "${project_dir}/requirements.txt" 2>/dev/null && fws="${fws},fastapi"
  fi

  echo "$fws" | sed 's/^,//'
}

# 테스트 프레임워크 자동 감지
_dna_detect_test_frameworks() {
  local tfs=""
  local project_dir="${GOLEM_PROJECT:-$(pwd)}"

  if [ -f "${project_dir}/package.json" ]; then
    grep -q '"jest"' "${project_dir}/package.json" 2>/dev/null && tfs="${tfs},jest"
    grep -q '"vitest"' "${project_dir}/package.json" 2>/dev/null && tfs="${tfs},vitest"
    grep -q '"cypress"' "${project_dir}/package.json" 2>/dev/null && tfs="${tfs},cypress"
    grep -q '"playwright"' "${project_dir}/package.json" 2>/dev/null && tfs="${tfs},playwright"
  fi
  if [ -f "${project_dir}/pom.xml" ]; then
    grep -q "junit" "${project_dir}/pom.xml" 2>/dev/null && tfs="${tfs},junit"
  fi
  if [ -f "${project_dir}/requirements.txt" ]; then
    grep -qi "pytest" "${project_dir}/requirements.txt" 2>/dev/null && tfs="${tfs},pytest"
  fi

  echo "$tfs" | sed 's/^,//'
}

# DNA 조회
dna_show() {
  if [ ! -f "$DNA_FILE" ]; then
    echo "[dna] 프로젝트 DNA 없음. forge-init 시 자동 생성됩니다."
    return
  fi

  echo "=== Project DNA ==="
  local project=$(grep -o '"project":"[^"]*"' "$DNA_FILE" | sed 's/"project":"//;s/"//')
  local langs=$(grep -o '"languages":"[^"]*"' "$DNA_FILE" | sed 's/"languages":"//;s/"//')
  local fws=$(grep -o '"frameworks":"[^"]*"' "$DNA_FILE" | sed 's/"frameworks":"//;s/"//')
  local arch=$(grep -o '"architecture":"[^"]*"' "$DNA_FILE" | sed 's/"architecture":"//;s/"//')
  local tests=$(grep -o '"test_frameworks":"[^"]*"' "$DNA_FILE" | sed 's/"test_frameworks":"//;s/"//')
  local domain=$(grep -o '"domain":"[^"]*"' "$DNA_FILE" | sed 's/"domain":"//;s/"//')

  echo "  프로젝트: ${project}"
  echo "  언어: ${langs}"
  echo "  프레임워크: ${fws}"
  echo "  아키텍처: ${arch}"
  echo "  테스트: ${tests}"
  echo "  도메인: ${domain}"
}

# DNA 비교 (SOUL 이동 시 적응도 체크)
# dna_compare <other_dna_file>
# 반환: 유사도 (0~100)
dna_compare() {
  local other_file="$1"

  if [ ! -f "$DNA_FILE" ] || [ ! -f "$other_file" ]; then
    echo "50"  # 비교 불가 → 중립
    return
  fi

  local score=0
  local checks=0

  # 언어 매칭
  local my_langs=$(grep -o '"languages":"[^"]*"' "$DNA_FILE" | sed 's/"languages":"//;s/"//')
  local other_langs=$(grep -o '"languages":"[^"]*"' "$other_file" | sed 's/"languages":"//;s/"//')
  checks=$((checks + 1))
  for lang in $(echo "$my_langs" | tr ',' ' '); do
    echo "$other_langs" | grep -qi "$lang" && score=$((score + 20))
  done

  # 프레임워크 매칭
  local my_fws=$(grep -o '"frameworks":"[^"]*"' "$DNA_FILE" | sed 's/"frameworks":"//;s/"//')
  local other_fws=$(grep -o '"frameworks":"[^"]*"' "$other_file" | sed 's/"frameworks":"//;s/"//')
  checks=$((checks + 1))
  for fw in $(echo "$my_fws" | tr ',' ' '); do
    echo "$other_fws" | grep -qi "$fw" && score=$((score + 25))
  done

  # 아키텍처 매칭
  local my_arch=$(grep -o '"architecture":"[^"]*"' "$DNA_FILE" | sed 's/"architecture":"//;s/"//')
  local other_arch=$(grep -o '"architecture":"[^"]*"' "$other_file" | sed 's/"architecture":"//;s/"//')
  checks=$((checks + 1))
  [ "$my_arch" = "$other_arch" ] && [ -n "$my_arch" ] && score=$((score + 20))

  # 도메인 매칭
  local my_domain=$(grep -o '"domain":"[^"]*"' "$DNA_FILE" | sed 's/"domain":"//;s/"//')
  local other_domain=$(grep -o '"domain":"[^"]*"' "$other_file" | sed 's/"domain":"//;s/"//')
  checks=$((checks + 1))
  [ "$my_domain" = "$other_domain" ] && [ -n "$my_domain" ] && score=$((score + 15))

  # 100 상한
  [ "$score" -gt 100 ] && score=100
  echo "$score"
}

# SOUL 이동 시 적응 가이드 생성
# dna_adaptation_guide <soul_name> <source_dna_file>
dna_adaptation_guide() {
  local soul_name="$1"
  local source_dna="$2"

  if [ ! -f "$DNA_FILE" ]; then
    echo "[dna] 현재 프로젝트 DNA 없음"
    return
  fi

  local similarity=$(dna_compare "$source_dna")

  echo "=== ${soul_name} 적응 가이드 ==="
  echo ""
  echo "  DNA 유사도: ${similarity}%"

  if [ "$similarity" -ge 80 ]; then
    echo "  판정: 높은 유사도 — 즉시 투입 가능"
  elif [ "$similarity" -ge 50 ]; then
    echo "  판정: 중간 유사도 — 일부 적응 필요"
  else
    echo "  판정: 낮은 유사도 — 상당한 적응 필요"
  fi

  echo ""

  # 차이점 분석
  local my_fws=$(grep -o '"frameworks":"[^"]*"' "$DNA_FILE" | sed 's/"frameworks":"//;s/"//')
  local src_fws=$(grep -o '"frameworks":"[^"]*"' "$source_dna" | sed 's/"frameworks":"//;s/"//')

  echo "  적응 필요 사항:"
  for fw in $(echo "$my_fws" | tr ',' ' '); do
    if ! echo "$src_fws" | grep -qi "$fw"; then
      echo "    - ${fw}: 새로운 프레임워크 — 전문 지식 보강 필요"
    fi
  done

  local my_langs=$(grep -o '"languages":"[^"]*"' "$DNA_FILE" | sed 's/"languages":"//;s/"//')
  local src_langs=$(grep -o '"languages":"[^"]*"' "$source_dna" | sed 's/"languages":"//;s/"//')
  for lang in $(echo "$my_langs" | tr ',' ' '); do
    if ! echo "$src_langs" | grep -qi "$lang"; then
      echo "    - ${lang}: 새로운 언어 — 학습 기간 필요"
    fi
  done
}
