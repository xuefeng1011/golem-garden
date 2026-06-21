#!/usr/bin/env bash
# eval.sh — 골든 태스크 스위트 러너 (P2-3, Terminal-Bench 태스크 규격 차용)
# Usage: source lib/eval.sh && eval_run --model sonnet
#
# 목적: 동일 하네스에서 모델/SOUL 교체 시 성능 회귀를 결정론 채점으로 측정.
# "하네스가 점수의 절반" — 엔진 변경의 효과를 수치로 확인하는 저울.
#
# 태스크 규격: tests/eval/<task-id>/
#   instruction.md  — SOUL에게 주는 태스크 텍스트 (필수)
#   verify.sh       — 결정론 채점기. $1=workspace, exit 0=pass / 1=fail (필수)
#   setup.sh        — 워크스페이스 픽스처 준비. $1=workspace (선택)
#
# 결과 기록: ${GOLEM_DIR}/eval/results.jsonl (append-only)
#   {"date","task","soul","model","result","duration_ms","tokens_out"}
# growth-log 오염 방지: eval 실행 중 GROWTH_DIR 을 eval 전용 경로로 우회.

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${GOLEM_ROOT}/lib/agent-runner.sh"

# 태스크 디렉토리: repo(GOLEM_ROOT) 우선, 없으면 프로젝트
_eval_tasks_dir() {
  if [ -d "${GOLEM_EVAL_TASKS:-}" ]; then
    echo "$GOLEM_EVAL_TASKS"
  elif [ -d "${GOLEM_ROOT}/tests/eval" ]; then
    echo "${GOLEM_ROOT}/tests/eval"
  else
    echo "${GOLEM_PROJECT:-$(pwd)}/tests/eval"
  fi
}

_eval_results_file() {
  echo "${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/eval/results.jsonl"
}

# 태스크 목록
eval_list() {
  local dir
  dir=$(_eval_tasks_dir)
  echo "=== Eval Golden Tasks (${dir}) ==="
  local d found=0
  for d in "${dir}"/*/; do
    [ -f "${d}instruction.md" ] || continue
    [ -f "${d}verify.sh" ] || continue
    found=$((found + 1))
    printf '  %-20s %s\n' "$(basename "$d")" "$(head -1 "${d}instruction.md")"
  done
  [ "$found" -eq 0 ] && echo "  (태스크 없음)"
  echo ""
  echo "총 ${found}개"
}

# 단일 태스크 실행 — 내부 헬퍼
# _eval_run_task <task_dir> <soul> <model>
# stdout: "result=pass|fail duration_ms=N tokens_out=N"
_eval_run_task() {
  local task_dir="$1"
  local soul="$2"
  local model="$3"

  local ws
  ws=$(mktemp -d "${TMPDIR:-/tmp}/golem-eval-XXXXXX") || return 1

  if [ -f "${task_dir}/setup.sh" ]; then
    bash "${task_dir}/setup.sh" "$ws" || { rm -rf "$ws"; echo "result=error"; return 1; }
  fi

  local instruction
  instruction=$(cat "${task_dir}/instruction.md")

  # 소환 — 워크스페이스를 cwd 로, growth-log 는 eval 전용 경로로 우회
  local out
  out=$(
    cd "$ws" || exit 1
    export GROWTH_DIR="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/eval/growth"
    mkdir -p "$GROWTH_DIR"
    AGENT_MODEL_OVERRIDE="$model" agent_run "$soul" "$instruction" 2>/dev/null
  )

  # usage 라인 파싱 (agent_run 마지막 줄 key=value 계약)
  local usage_line duration_ms tokens_out
  usage_line=$(printf '%s' "$out" | grep '^<usage>' | tail -1)
  duration_ms=$(printf '%s' "$usage_line" | grep -o 'duration_ms=[0-9]*' | cut -d= -f2)
  tokens_out=$(printf '%s' "$usage_line" | grep -o 'tokens_out=[0-9]*' | cut -d= -f2)

  # 결정론 채점
  local result="fail"
  if bash "${task_dir}/verify.sh" "$ws" >/dev/null 2>&1; then
    result="pass"
  fi

  rm -rf "$ws"
  echo "result=${result} duration_ms=${duration_ms:-0} tokens_out=${tokens_out:-0}"
}

# 배치 러너
# eval_run [--model <m>] [--soul <s>] [--task <id>]
eval_run() {
  local model="" soul="ryn" only_task=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --model) model="$2"; shift ;;
      --soul)  soul="$2"; shift ;;
      --task)  only_task="$2"; shift ;;
      *) echo "[eval] 알 수 없는 옵션: $1" >&2; return 1 ;;
    esac
    shift
  done

  local dir
  dir=$(_eval_tasks_dir)
  if [ ! -d "$dir" ]; then
    echo "[eval] ERROR: 태스크 디렉토리 없음: ${dir}" >&2
    return 1
  fi

  local results_file
  results_file=$(_eval_results_file)
  mkdir -p "$(dirname "$results_file")"

  local model_label="${model:-soul-default}"
  echo "=== forge eval — soul=${soul} model=${model_label} ==="
  echo ""

  local d task_id line result duration tokens
  local total=0 passed=0
  local date_str
  date_str=$(date +%Y-%m-%d)

  for d in "${dir}"/*/; do
    [ -f "${d}instruction.md" ] || continue
    [ -f "${d}verify.sh" ] || continue
    task_id=$(basename "$d")
    [ -n "$only_task" ] && [ "$task_id" != "$only_task" ] && continue

    total=$((total + 1))
    printf '  [%d] %-20s ... ' "$total" "$task_id"

    line=$(_eval_run_task "$d" "$soul" "$model")
    result=$(printf '%s' "$line" | grep -o 'result=[a-z]*' | cut -d= -f2)
    duration=$(printf '%s' "$line" | grep -o 'duration_ms=[0-9]*' | cut -d= -f2)
    tokens=$(printf '%s' "$line" | grep -o 'tokens_out=[0-9]*' | cut -d= -f2)

    if [ "$result" = "pass" ]; then
      passed=$((passed + 1))
      printf 'PASS (%sms)\n' "${duration:-0}"
    else
      printf 'FAIL (%sms)\n' "${duration:-0}"
    fi

    printf '{"date":"%s","task":"%s","soul":"%s","model":"%s","result":"%s","duration_ms":%s,"tokens_out":%s}\n' \
      "$date_str" "$task_id" "$soul" "$model_label" "$result" "${duration:-0}" "${tokens:-0}" \
      >> "$results_file"
  done

  echo ""
  if [ "$total" -eq 0 ]; then
    echo "[eval] 실행된 태스크 없음 (--task 오타?)"
    return 1
  fi
  echo "결과: ${passed}/${total} pass — 기록: ${results_file}"
  [ "$passed" -eq "$total" ] && return 0 || return 1
}

# 모델별 집계 리포트
eval_report() {
  local results_file
  results_file=$(_eval_results_file)
  if [ ! -f "$results_file" ]; then
    echo "[eval] 기록 없음. 먼저 forge eval 을 실행하세요."
    return 1
  fi

  echo "=== Eval Report (${results_file}) ==="
  echo ""
  printf '%-22s %-8s %-8s %s\n' "Model" "Pass" "Total" "Rate"
  printf '%-22s %-8s %-8s %s\n' "-----" "----" "-----" "----"

  local m p t
  for m in $(grep -o '"model":"[^"]*"' "$results_file" | sed 's/"model":"//;s/"//' | sort -u); do
    t=$(grep -c "\"model\":\"${m}\"" "$results_file")
    p=$(grep "\"model\":\"${m}\"" "$results_file" | grep -c '"result":"pass"')
    printf '%-22s %-8s %-8s %s%%\n' "$m" "$p" "$t" "$((p * 100 / t))"
  done
}
