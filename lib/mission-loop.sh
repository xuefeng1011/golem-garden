#!/usr/bin/env bash
# mission-loop.sh — `forge mission run` 결정론 실행 루프 (PERF P1-6)
#
# SKILL.md 프롬프트에만 존재하던 execute↔verify 루프 계약을 코드로 강제한다:
#   · 사이클 상한: GOLEM_MISSION_MAX_CYCLES (기본 3 — "검증 3사이클 실패 정지")
#   · 태스크 재시도 상한: GOLEM_MISSION_MAX_ATTEMPTS (기본 3)
#   · verify 자동 호출: verify.sh(verify_run) 재사용 — author≠verifier 코드 가드 작동
#   · budget 소비: budget_record 후 BUDGET_EXCEEDED/STAGNATING 센티널로 결정론 정지
#   · 스턱 디텍터: 사이클 종료마다 (git diff + 실패사유) cksum — 직전과 동일하면 STUCK
#   · 완료 센티널: <promise>COMPLETE</promise>
#
# LLM(스킬)의 몫: 요구사항 인터뷰, 태스크 분해(set-tasks), 정지 시 재계획, 완주 보고.
#
# 루프 상태는 state.json 이 아니라 ${mission}/loop.json 에 격리한다 —
# state.json 의 task 객체 스키마(mission.sh grep 패턴 계약 4곳)를 건드리지 않기 위함.
#
# mission_run 반환 코드:
#   0=검증 통과 완료 / 1=태스크 실패·설정 오류 / 2=예산 정지(EXCEEDED/STAGNATING)
#   3=STUCK(진전 없음) / 4=사이클 상한 도달
#
# 주의: agent_run/verify_run/error_retry/budget_record 는 호출 시점에 참조한다
#       (bats 가 함수 재정의로 mock — 소싱 시점 바인딩 금지).

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${GOLEM_ROOT}/lib/mission.sh"

GOLEM_MISSION_MAX_CYCLES="${GOLEM_MISSION_MAX_CYCLES:-3}"
GOLEM_MISSION_MAX_ATTEMPTS="${GOLEM_MISSION_MAX_ATTEMPTS:-3}"

# 루프 상태 저장 (원자적 tmp+mv)
# _mission_loop_save <mdir> <cycles> <stuck_sig> <last_failure>
_mission_loop_save() {
  local mdir="$1" cycles="$2" sig="$3" failure="$4"
  local esc tmp
  esc=$(_json_escape "$failure")
  tmp="${mdir}/loop.json.tmp"
  printf '{"cycles":%d,"stuck_sig":"%s","last_failure":"%s"}\n' \
    "$cycles" "$sig" "$esc" > "$tmp" && mv "$tmp" "${mdir}/loop.json"
}

# 의존 lib 지연 로드 — 함수가 이미 정의돼 있으면(테스트 mock 포함) 재소싱하지 않는다
_mission_loop_deps() {
  command -v agent_run             >/dev/null 2>&1 || source "${GOLEM_ROOT}/lib/agent-runner.sh"
  command -v verify_run            >/dev/null 2>&1 || source "${GOLEM_ROOT}/lib/verify.sh"
  command -v error_retry           >/dev/null 2>&1 || source "${GOLEM_ROOT}/lib/error-recovery.sh"
  command -v budget_record         >/dev/null 2>&1 || source "${GOLEM_ROOT}/lib/budget.sh"
  command -v triage_estimate_turns >/dev/null 2>&1 || source "${GOLEM_ROOT}/lib/triage.sh"
}

# C-2 스텝별 턴 예산 산정 — AGENT_MAX_TURNS_OVERRIDE 로 agent_run 에 인라인 전달할
# 값을 stdout 에 정수로 낸다. 킬스위치 GOLEM_TURN_BUDGET=0 이면 빈 문자열
# (agent-runner 가 override 부재로 처리해 frontmatter/rank 기본값으로 폴백).
# _mission_step_budget <soul> <task_text>
_mission_step_budget() {
  local soul="$1" task="$2"
  [ "${GOLEM_TURN_BUDGET:-1}" = "0" ] && return 0

  local rank est_files turns
  rank=$(soul_get_field "$(_resolve_soul_file "$soul")" "rank")
  est_files=$(_triage_explore_files "$task" 2>/dev/null | grep -c '[^[:space:]]')
  turns=$(triage_estimate_turns "$rank" "$est_files")

  echo "[BUDGET] turns=${turns} est_files=${est_files} rank=${rank}" >&2
  echo "$turns"
}

# spec.md 의 "## 성공 기준" 섹션 본문 추출 (verify target 조립용)
_mission_criteria() {
  local mdir="$1"
  awk '/^## 성공 기준$/{f=1;next} /^## /{f=0} f' "${mdir}/spec.md" 2>/dev/null \
    | sed '/^[[:space:]]*$/d' | head -5
}

# budget 센티널 검사 — agent_run usage 라인의 tokens_out 을 소비해 기록하고
# EXCEEDED/STAGNATING 이면 비-0 반환 (stdout 에 사유 출력)
# _mission_budget_gate <soul> <agent_output>
_mission_budget_gate() {
  local soul="$1" out="$2"
  local t_out b_out
  t_out=$(printf '%s' "$out" | grep -o 'tokens_out=[0-9]*' | tail -1 | cut -d= -f2)
  b_out=$(budget_record "$soul" "${t_out:-0}" 0 2>/dev/null)
  case "$b_out" in
    *BUDGET_EXCEEDED*)   echo "BUDGET_EXCEEDED";   return 1 ;;
    *BUDGET_STAGNATING*) echo "BUDGET_STAGNATING"; return 1 ;;
  esac
  return 0
}

# mission_run <id> [default_soul] [verifier_soul]
mission_run() {
  local id="$1" default_soul="${2:-}" verifier_soul="${3:-zen}"
  local mdir
  mdir=$(_mission_resolve "$id")
  if [ -z "$mdir" ]; then echo "[mission] ERROR: 미션 없음: ${id}" >&2; return 1; fi

  local state="${mdir}/state.json"
  local prog total
  prog=$(_mission_progress "$state")
  total="${prog#* }"
  if [ "${total:-0}" -eq 0 ]; then
    echo "[mission] ERROR: 태스크가 없습니다 — 'forge mission set-tasks' 로 먼저 분해하세요" >&2
    return 1
  fi

  _mission_loop_deps

  local goal criteria
  goal=$(_json_unescape "$(_json_get_string "$(head -1 "$state")" goal)")
  criteria=$(_mission_criteria "$mdir")
  [ -z "$criteria" ] && criteria="$goal"

  # 루프 상태 복원 (재개 지원 — 이전 run 의 cycles/서명을 이어받는다)
  local cycles=0 prev_sig="" last_failure=""
  if [ -f "${mdir}/loop.json" ]; then
    cycles=$(grep -o '"cycles":[0-9]*' "${mdir}/loop.json" | head -1 | cut -d: -f2)
    prev_sig=$(_json_scalar "$(head -1 "${mdir}/loop.json")" stuck_sig)
    last_failure=$(_json_unescape "$(_json_get_string "$(head -1 "${mdir}/loop.json")" last_failure)")
    cycles=${cycles:-0}
  fi

  echo "[mission] ▶ run: ${id} (cycle ${cycles}/${GOLEM_MISSION_MAX_CYCLES}, verifier=${verifier_soul})"

  local last_soul="$default_soul"
  while [ "$cycles" -lt "$GOLEM_MISSION_MAX_CYCLES" ]; do

    # ── 태스크 루프: pending 소진 ─────────────────────────────
    local next idx task soul attempts rc out prompt gate step_turns
    while :; do
      next=$(mission_next "$id") || return 1
      [ "$next" = "none" ] && break
      local _tab=$'\t'
      idx="${next%%${_tab}*}"
      task="${next#*${_tab}}"

      soul="$default_soul"
      if [ -z "$soul" ]; then
        soul=$(soul_find_best_match "$task")
      fi
      if [ -z "$soul" ]; then
        echo "[mission] ERROR: 태스크 ${idx} 에 배정할 SOUL 없음 — 'mission run <id> <soul>' 로 지정하세요" >&2
        return 1
      fi
      last_soul="$soul"

      mission_task "$id" "$idx" in_progress "$soul" >/dev/null
      echo "[mission] ── task ${idx} (${soul}): ${task}"

      # C-2 턴 예산 산정 — 스텝 규모 기반 캡 (킬스위치 GOLEM_TURN_BUDGET=0)
      step_turns=$(_mission_step_budget "$soul" "$task")

      # 초기 프롬프트 — 직전 검증 실패 피드백이 있으면 주입
      prompt="$task"
      if [ -n "$last_failure" ]; then
        prompt="${task}

[직전 검증 실패 피드백 — 이 사유를 해소하라]
${last_failure}"
      fi

      attempts=0
      while :; do
        rc=0
        if out=$(VERIFY_AUTHOR_SOUL="$soul" AGENT_MAX_TURNS_OVERRIDE="${step_turns}" agent_run "$soul" "$prompt"); then rc=0; else rc=$?; fi
        printf '%s\n' "$out"

        # 예산 게이트 — 소환마다 소비·판정 (수확체감 계층과 루프 연결)
        gate=""
        if ! gate=$(_mission_budget_gate "$soul" "$out"); then
          _mission_loop_save "$mdir" "$cycles" "$prev_sig" "$last_failure"
          mission_task "$id" "$idx" pending "$soul" >/dev/null
          echo "[mission] ■ STOP: ${gate} — 예산 계층 정지 (task ${idx} 는 pending 복귀)"
          return 2
        fi

        [ "$rc" -eq 0 ] && break

        attempts=$((attempts + 1))
        if [ "$attempts" -ge "$GOLEM_MISSION_MAX_ATTEMPTS" ]; then
          mission_task "$id" "$idx" failed "$soul" >/dev/null
          _mission_loop_save "$mdir" "$cycles" "$prev_sig" "실행 ${GOLEM_MISSION_MAX_ATTEMPTS}회 실패: task ${idx}"
          echo "[mission] ■ STOP: task ${idx} 가 ${GOLEM_MISSION_MAX_ATTEMPTS}회 연속 실패 — 재분해/SOUL 교체 필요"
          return 1
        fi
        echo "[mission]    retry ${attempts}/${GOLEM_MISSION_MAX_ATTEMPTS} (rc=${rc})"
        # 실패 컨텍스트 주입 프롬프트 (error-recovery 재배선) — 생성 실패 시 원본 유지
        if ! prompt=$(error_retry "$soul" "$task" "직전 시도 실패 (rc=${rc})" "$attempts" 2>/dev/null); then
          prompt="$task"
        fi
      done

      mission_task "$id" "$idx" done "$soul" >/dev/null
    done

    # ── verify 게이트: author≠verifier 코드 가드는 verify.sh 가 강제 ──────
    echo "[mission] ── verify (author=${last_soul:-?}, verifier=${verifier_soul})"
    local v_rc=0 v_out=""
    if v_out=$(VERIFY_AUTHOR_SOUL="$last_soul" verify_run "미션 '${goal}' — 성공 기준: ${criteria}" "$verifier_soul"); then
      v_rc=0
    else
      v_rc=$?
    fi
    printf '%s\n' "$v_out"

    if [ "$v_rc" -eq 0 ]; then
      mission_complete "$id"
      rm -f "${mdir}/loop.json"
      echo "<promise>COMPLETE</promise>"
      return 0
    fi

    # ── verify FAIL: 사이클 증가 + 스턱 판정 + 마지막 태스크 재개방 ────────
    cycles=$((cycles + 1))
    last_failure=$(printf '%s' "$v_out" | tail -5)

    local sig
    sig=$( { git -C "${GOLEM_PROJECT:-$(pwd)}" diff HEAD 2>/dev/null; printf '%s' "$last_failure"; } \
      | cksum | awk '{print $1}')
    if [ -n "$prev_sig" ] && [ "$sig" = "$prev_sig" ]; then
      _mission_loop_save "$mdir" "$cycles" "$sig" "$last_failure"
      echo "[mission] ■ STOP: STUCK — 직전 사이클과 변경/실패사유 동일 (진전 없음)"
      return 3
    fi
    prev_sig="$sig"
    _mission_loop_save "$mdir" "$cycles" "$sig" "$last_failure"

    if [ "$cycles" -ge "$GOLEM_MISSION_MAX_CYCLES" ]; then
      break
    fi

    # 마지막 태스크 재개방 — 실패 피드백을 다음 사이클 입력으로 주입
    local reopen_idx=$((total - 1))
    mission_task "$id" "$reopen_idx" pending >/dev/null
    echo "[mission] ↻ cycle ${cycles}/${GOLEM_MISSION_MAX_CYCLES} — task ${reopen_idx} 재개방 (검증 피드백 주입)"
  done

  echo "[mission] ■ STOP: 검증 ${GOLEM_MISSION_MAX_CYCLES}사이클 실패 — 정지 조건 (c). 재계획이 필요합니다"
  return 4
}
