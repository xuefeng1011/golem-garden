#!/usr/bin/env bash
# triage.sh — 태스크 복잡도 결정론 점수기 (P1 C-1 전반부)
# LLM 호출 없이 grep/awk 신호만으로 T0/T1/T2 티어를 판정한다.
# 정본 설계: docs/UX-EXPERT-PLAN.md C-1 (forge do 트리아지 디스패처)
#
# Usage: source lib/triage.sh && triage_run "task text"

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${GOLEM_ROOT}/lib/explore.sh"
source "${GOLEM_ROOT}/lib/soul-parser.sh"
source "${GOLEM_ROOT}/lib/mission.sh"

# ═══════════════════════════════════════════════════════
# _triage_explore_files <task_text>
# 한글 태스크 보정: 한글 조사가 붙은 단어는 explore 매칭이 안 되므로,
# 경로/파일명 패턴(lib/flow.sh 등)과 영문 식별자(4자+)를 우선 키워드로 뽑는다.
# 태스크에 실존하는 파일 경로가 직접 등장하면 그 파일을 최소 히트로 강제 포함한다.
# explore_files 의 grep 폴백 백엔드는 BRE라 "|" 가 리터럴 취급되어 OR 조회가
# 깨지므로(alternation 미지원), 키워드별로 개별 조회 후 병합한다.
# explore/grep을 건드리는 유일한 지점 — bats에서는 이 함수 하나만
# 오버라이드하면 결정론 격리가 된다.
# stdout: 히트 파일 경로, 줄당 1개, 중복 제거.
# 호출부가 라인 수를 세어 고유 파일 수로 사용한다.
# ═══════════════════════════════════════════════════════
_triage_explore_files() {
  local task_text="$1"
  local project_root="${GOLEM_PROJECT:-${GOLEM_ROOT}}"
  local tok
  local -a path_kw=() ident_kw=() keywords=()

  while IFS= read -r tok; do
    [ -n "$tok" ] && path_kw+=("$tok")
  done < <(printf '%s' "$task_text" | grep -oE '[A-Za-z0-9_./-]+\.[A-Za-z]{2,5}')

  while IFS= read -r tok; do
    [ -n "$tok" ] && ident_kw+=("$tok")
  done < <(printf '%s' "$task_text" | grep -oE '[A-Za-z_][A-Za-z0-9_]{3,}')

  local seen_kw=$'\n'
  for tok in "${path_kw[@]}" "${ident_kw[@]}"; do
    case "$seen_kw" in *$'\n'"$tok"$'\n'*) continue ;; esac
    seen_kw="${seen_kw}${tok}"$'\n'
    keywords+=("$tok")
    [ "${#keywords[@]}" -ge 5 ] && break
  done

  # 영문 토큰이 전혀 없으면 기존 방식(공백 분리 4자+)으로 폴백
  if [ "${#keywords[@]}" -eq 0 ]; then
    while IFS= read -r tok; do
      keywords+=("$tok")
    done < <(printf '%s' "$task_text" | tr '[:space:]' '\n' \
      | awk 'length($0)>=4 && !seen[$0]++ {print}' | head -5)
  fi

  [ "${#keywords[@]}" -eq 0 ] && return 0

  local merged=$'\n' hit
  for tok in "${path_kw[@]}"; do
    [ -f "${project_root}/${tok}" ] || continue
    hit="${project_root}/${tok}"
    case "$merged" in *$'\n'"$hit"$'\n'*) continue ;; esac
    merged="${merged}${hit}"$'\n'
    printf '%s\n' "$hit"
  done

  for tok in "${keywords[@]}"; do
    while IFS= read -r hit; do
      [ -z "$hit" ] && continue
      # 런타임 로그/벤더 산출물 노이즈 제외 — grep 폴백은 이런 경로를
      # 배제하지 않아 "retry" 류 흔한 단어가 .golem/runs, .venv 등에서
      # 대량 오탐되어 files 임계를 왜곡한다.
      case "$hit" in
        */.golem/runs/*|*/.venv/*|*/node_modules/*|*/.git/*|*/dist/*|*/__pycache__/*)
          continue ;;
      esac
      case "$merged" in *$'\n'"$hit"$'\n'*) continue ;; esac
      merged="${merged}${hit}"$'\n'
      printf '%s\n' "$hit"
    done < <(explore_files "$tok" "$project_root" 2>/dev/null \
      | awk '/matches/ { sub(/^ *[0-9]+ matches +/, ""); print }')
  done
}

# ═══════════════════════════════════════════════════════
# _triage_explicit_paths <task_text>
# 태스크에 슬래시+확장자로 명시된 경로(예: lib/flow.sh, web/gateway/x.py)만
# 추출한다. explore 히트는 "식별자가 언급된 파일 수"(중심성)를 재는 것이지
# 변경 범위가 아니어서, 단일/소수 파일을 명시한 사소 태스크가 문서/테스트
# 전반의 언급 때문에 과대 판정(T2)되는 부작용이 있었다. 명시 경로가 있으면
# 이 목록만이 files/domains 산정의 근거가 된다(explore 미사용, 결정론).
# stdout: 고유 경로 원문, 줄당 1개. 명시 경로가 없으면 빈 출력.
# ═══════════════════════════════════════════════════════
_triage_explicit_paths() {
  local task_text="$1"
  local tok
  local seen=$'\n'

  # URL 은 통째로 선제 제거 — grep 토큰화가 스킴(://)을 떼어내
  # example.com/x.md 가 경로로 오인되는 것을 차단
  task_text=$(printf '%s' "$task_text" | sed 's|[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]]*| |g')

  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    case "$tok" in
      *://*) continue ;;   # URL 제외
      */*) : ;;            # 슬래시 포함 경로
      # 슬래시 없는 순수 파일명(README.md 등)은 코드/문서 확장자 화이트리스트만 허용
      # — .com 등 도메인 토큰 오탐 차단 (실사용 실측: README.md 태스크가 T2 과대 판정)
      *.sh|*.bash|*.py|*.md|*.ts|*.tsx|*.js|*.vue|*.json|*.yml|*.yaml|*.bats|*.toml|*.txt|*.ps1) : ;;
      *) continue ;;
    esac
    case "$seen" in *$'\n'"$tok"$'\n'*) continue ;; esac
    seen="${seen}${tok}"$'\n'
    printf '%s\n' "$tok"
  done < <(printf '%s' "$task_text" | grep -oE '[A-Za-z0-9_./-]+\.[A-Za-z]{2,5}')
}

# ═══════════════════════════════════════════════════════
# _triage_domain_count <파일목록>
# 경로 버킷: lib/|forge.sh|tests/bats → bash, web/gateway → python,
# web/client → vue. 그 외는 etc(카운트 제외). 고유 버킷 수를 반환.
# ═══════════════════════════════════════════════════════
_triage_domain_count() {
  local file_list="$1"

  [ -z "$file_list" ] && { echo 0; return 0; }

  printf '%s\n' "$file_list" | awk '
    {
      bucket = ""
      if (index($0, "lib/") > 0 || index($0, "forge.sh") > 0 || index($0, "tests/bats") > 0) bucket = "bash"
      else if (index($0, "web/gateway") > 0) bucket = "python"
      else if (index($0, "web/client") > 0) bucket = "vue"
      if (bucket != "" && !seen[bucket]++) count++
    }
    END { print count + 0 }
  '
}

# ═══════════════════════════════════════════════════════
# _triage_enum_score <task_text>
# 열거/접속사 신호: '+', 쉼표, '그리고', ' 및 ' 출현 수 + (2줄 이상이면 +1).
# ═══════════════════════════════════════════════════════
_triage_enum_score() {
  local task_text="$1"

  printf '%s\n' "$task_text" | awk '
    {
      lines++
      plus  += gsub(/\+/, "+")
      comma += gsub(/,/, ",")
      conj  += gsub(/그리고/, "그리고")
      mich  += gsub(/ 및 /, " 및 ")
    }
    END {
      score = plus + comma + conj + mich
      if (lines >= 2) score += 1
      print score + 0
    }
  '
}

# ── 내부: 고정 문자열 키워드 포함 여부 ──
# grep -iF 는 이 머신 grep 3.0 에서 고장(사용 금지) — awk index()로 대체.
_triage_has_keyword() {
  local text="$1" kw="$2"
  printf '%s' "$text" | awk -v k="$kw" '
    index($0, k) > 0 { found=1 }
    END { exit (found ? 0 : 1) }
  '
}

# ═══════════════════════════════════════════════════════
# _triage_ambiguity <task_text>
# 숫자 / 파일명(.확장자) / 테스트·검증 언급 / 구체 함수명 패턴 중
# 하나라도 있으면 low, 전혀 없으면 high.
# ═══════════════════════════════════════════════════════
_triage_ambiguity() {
  local task_text="$1"
  local concrete=0

  printf '%s' "$task_text" | grep -qE '[0-9]' && concrete=1
  printf '%s' "$task_text" | grep -qE '[A-Za-z0-9_./-]+\.[A-Za-z]{2,5}' && concrete=1
  printf '%s' "$task_text" | grep -qE '[A-Za-z_][A-Za-z0-9_]*\(\)' && concrete=1
  _triage_has_keyword "$task_text" "테스트" && concrete=1
  _triage_has_keyword "$task_text" "검증" && concrete=1
  _triage_has_keyword "$task_text" "test" && concrete=1
  _triage_has_keyword "$task_text" "bats" && concrete=1

  if [ "$concrete" -eq 1 ]; then
    echo low
  else
    echo high
  fi
}

# ═══════════════════════════════════════════════════════
# triage_run <task_text>
# 종합 판정. 첫 줄은 파싱 가능한 TRIAGE 요약, 이어서 사람용 설명.
# 티어 규칙 (UX-EXPERT-PLAN C-1):
#   T0 = files<=2 && domains<=1 && ambiguity=low
#   T2 = files>=9 || domains>=3 || ambiguity=high
#   그 외 T1
# ═══════════════════════════════════════════════════════
triage_run() {
  local task_text="$1"
  local file_list files domains enum ambiguity tier explicit_list

  explicit_list=$(_triage_explicit_paths "$task_text")

  if [ -n "$(printf '%s' "$explicit_list" | tr -d '[:space:]')" ]; then
    # 명시 경로 우선 — explore 히트(중심성)는 쓰지 않는다.
    files=$(printf '%s\n' "$explicit_list" | grep -c '[^[:space:]]')
    _triage_has_keyword "$task_text" "테스트" && files=$((files + 1))
    domains=$(_triage_domain_count "$explicit_list")
  else
    file_list=$(_triage_explore_files "$task_text")
    files=$(printf '%s\n' "$file_list" | grep -c '[^[:space:]]')
    domains=$(_triage_domain_count "$file_list")
  fi

  enum=$(_triage_enum_score "$task_text")
  ambiguity=$(_triage_ambiguity "$task_text")

  if [ "$files" -le 2 ] && [ "$domains" -le 1 ] && [ "$ambiguity" = "low" ]; then
    tier=T0
  elif [ "$files" -ge 9 ] || [ "$domains" -ge 3 ] || [ "$ambiguity" = "high" ]; then
    tier=T2
  else
    tier=T1
  fi

  echo "TRIAGE tier=${tier} files=${files} domains=${domains} enum=${enum} ambiguity=${ambiguity}"
  echo ""
  echo "[triage] 태스크 복잡도 판정"
  echo "  파일 히트 : ${files}"
  echo "  도메인 수 : ${domains}"
  echo "  열거 신호 : ${enum}"
  echo "  모호성    : ${ambiguity}"
  echo "  → 티어    : ${tier}"
}

# ═══════════════════════════════════════════════════════
# _triage_rank_score <rank>
# rank 서열 비교용 정수화 (동률 SOUL 선택 시 tiebreak).
# ═══════════════════════════════════════════════════════
_triage_rank_score() {
  case "$1" in
    novice) echo 1 ;;
    junior) echo 2 ;;
    senior) echo 3 ;;
    lead)   echo 4 ;;
    master) echo 5 ;;
    *)      echo 0 ;;
  esac
}

# ═══════════════════════════════════════════════════════
# triage_pick_soul <task_text>
# T0 자동 실행용 SOUL 선택 — _all_soul_files 전체(Director 제외)를 순회해
# frontmatter specialty 와 태스크 키워드(4자+ 고유 단어) 겹침 최다 SOUL을 고른다.
# 동률 → rank 높은 쪽, 그래도 동률 → 먼저 나온(_all_soul_files 순서상 앞선) SOUL.
# stdout: "<name>\t<reason>" (매칭 실패 시 빈 문자열 + return 1)
# ═══════════════════════════════════════════════════════
triage_pick_soul() {
  local task_text="$1"
  local keywords_lower
  keywords_lower=$(printf '%s' "$task_text" | tr '[:space:]' '\n' \
    | awk 'length($0)>=4 && !seen[$0]++ {print tolower($0)}')

  local best_name="" best_score=-1 best_rank=-1 best_specialty=""
  local soul_file
  while IFS= read -r soul_file; do
    [ -f "$soul_file" ] || continue
    soul_parse "$soul_file"
    [ "$SOUL_ROLE" = "director" ] && continue

    local specialty_lower
    specialty_lower=$(printf '%s' "$SOUL_SPECIALTY" | tr '[:upper:]' '[:lower:]')

    local score=0 kw
    for kw in $keywords_lower; do
      if printf '%s' "$specialty_lower" | awk -v k="$kw" 'index($0,k)>0{f=1} END{exit(f?0:1)}'; then
        score=$((score + 1))
      fi
    done

    local rank_score
    rank_score=$(_triage_rank_score "$SOUL_RANK")

    if [ "$score" -gt "$best_score" ] || { [ "$score" -eq "$best_score" ] && [ "$rank_score" -gt "$best_rank" ]; }; then
      best_score="$score"
      best_rank="$rank_score"
      best_name="$SOUL_NAME"
      best_specialty="$SOUL_SPECIALTY"
    fi
  done < <(_all_soul_files)

  if [ -z "$best_name" ]; then
    return 1
  fi
  printf '%s\t겹침 %s개 (specialty: %s)\n' "$best_name" "$best_score" "$best_specialty"
}

# ═══════════════════════════════════════════════════════
# _triage_do_t1 <task_text> — T1 판정: 실행하지 않고 권고만 출력.
# ═══════════════════════════════════════════════════════
_triage_do_t1() {
  local task_text="$1"
  echo "[TRIAGE] T1 판정 — 권장: forge build: ${task_text}"
}

# ═══════════════════════════════════════════════════════
# _triage_do_t0 <task_text> — T0 판정: specialty 매칭 SOUL 1개 선정 후 직행.
# ═══════════════════════════════════════════════════════
_triage_do_t0() {
  local task_text="$1"
  local pick name reason

  pick=$(triage_pick_soul "$task_text")
  if [ -z "$pick" ]; then
    echo "[TRIAGE] T0 판정이지만 매칭 SOUL 없음 — 권장: forge build: ${task_text}" >&2
    return 1
  fi
  name=$(printf '%s' "$pick" | cut -f1)
  reason=$(printf '%s' "$pick" | cut -f2-)

  echo "[TRIAGE] T0 → SOUL 선택: ${name} — ${reason}"
  command -v agent_run >/dev/null 2>&1 || source "${GOLEM_ROOT}/lib/agent-runner.sh"
  agent_run "$name" "$task_text"
}

# ═══════════════════════════════════════════════════════
# _triage_do_t2 <task_text> — T2 판정: Nex 분해 요청 → mission 생성(승인 게이트).
# 분해 실패(JSON 추출 불가) 시 T1 권고로 강등한다.
# ═══════════════════════════════════════════════════════
_triage_do_t2() {
  local task_text="$1"
  local decompose_prompt resp last_line mission_id

  decompose_prompt="다음 태스크를 하위 작업으로 분해하라: ${task_text}
mission set-tasks-json 이 소비하는 JSON 배열([{\"id\",\"soul\",\"task\",\"deps\"}...], 1-depth, task 에 리터럴 },{ 금지)만 마지막 줄에 출력하라."

  command -v agent_run >/dev/null 2>&1 || source "${GOLEM_ROOT}/lib/agent-runner.sh"
  resp=$(agent_run nex "$decompose_prompt")

  last_line=$(printf '%s\n' "$resp" | awk '
    { line = $0; sub(/^[ \t]+/, "", line)
      if (line ~ /^\{/ || line ~ /^\[/) last = line }
    END { print last }
  ')

  if [ -z "$last_line" ]; then
    echo "[TRIAGE] T2 분해 실패 (JSON 추출 불가) — T1 권고로 강등"
    echo "--- Nex 원문 ---"
    echo "$resp"
    _triage_do_t1 "$task_text"
    return 1
  fi

  mission_id=$(mission_init "$task_text" "" "" "")
  if ! mission_set_tasks_json "$mission_id" "$last_line" >/dev/null; then
    echo "[TRIAGE] T2 분해 실패 (JSON 파싱 불가) — T1 권고로 강등"
    _triage_do_t1 "$task_text"
    return 1
  fi

  echo "[TRIAGE] T2 → mission 생성됨: ${mission_id}"
  echo "mission 생성됨: forge mission run ${mission_id} 로 실행"
}

# ═══════════════════════════════════════════════════════
# triage_estimate_turns <rank> <est_files>
# C-2 턴 예산 산정: base(rank) + est_files×3 + 테스트 실행 여유 2, 상한 60 클램프.
# 계수는 UX-EXPERT-PLAN C-2 초안 그대로 (growth log 실측 보정은 후속).
# est_files 가 비정수/음수면 0 취급. stdout: 정수 1개.
# ═══════════════════════════════════════════════════════
triage_estimate_turns() {
  local rank="$1" est_files="$2"
  local base turns

  case "$rank" in
    novice) base=8 ;;
    junior) base=12 ;;
    *)      base=16 ;;
  esac

  case "$est_files" in
    ''|*[!0-9]*) est_files=0 ;;
  esac

  turns=$((base + est_files * 3 + 2))
  [ "$turns" -gt 60 ] && turns=60

  echo "$turns"
}

# ═══════════════════════════════════════════════════════
# forge_do <task_text> — `forge do` 진입점. triage_run 결과 tier 에 따라
# T0/T1/T2 기어를 분기한다 (UX-EXPERT-PLAN C-1).
# ═══════════════════════════════════════════════════════
forge_do() {
  local task_text="$1"
  local tier

  tier=$(triage_run "$task_text" | head -1 | grep -o 'tier=T[0-2]' | sed 's/tier=//')

  case "$tier" in
    T0) _triage_do_t0 "$task_text" ;;
    T2) _triage_do_t2 "$task_text" ;;
    *)  _triage_do_t1 "$task_text" ;;
  esac
}
