#!/usr/bin/env bash
# forge.sh — GolemGarden CLI 진입점
# Usage: bash forge.sh <command> [args...]

# set -e 제거: 라이브러리 내 조건문이 false 반환 시 스크립트 중단 방지

# 글로벌: GolemGarden 설치 경로 (라이브러리, 템플릿, 도메인팩)
GOLEM_ROOT="$(cd "$(dirname "$0")" && pwd)"

# 프로젝트별: .golem/ 디렉토리 (forge-board, souls 오버라이드, growth-log)
# 우선순위: GOLEM_PROJECT 환경변수 → pwd에 .golem/이 있으면 → GOLEM_ROOT 폴백
if [ -n "${GOLEM_PROJECT:-}" ]; then
  GOLEM_DIR="${GOLEM_PROJECT}/.golem"
elif [ -d "$(pwd)/.golem" ]; then
  GOLEM_PROJECT="$(pwd)"
  GOLEM_DIR="$(pwd)/.golem"
elif [ -d "${OLDPWD:-}/.golem" ]; then
  # Claude Code가 cd 후 실행한 경우 OLDPWD 확인
  GOLEM_PROJECT="${OLDPWD}"
  GOLEM_DIR="${OLDPWD}/.golem"
else
  GOLEM_PROJECT="$(pwd)"
  GOLEM_DIR="${GOLEM_ROOT}/.golem"
fi

# .golem/ 없으면 자동 생성
if [ ! -d "${GOLEM_DIR}" ]; then
  mkdir -p "${GOLEM_DIR}/souls"
  mkdir -p "${GOLEM_DIR}/growth-log"
  mkdir -p "${GOLEM_DIR}/mailbox"
  mkdir -p "${GOLEM_DIR}/sessions"
  mkdir -p "${GOLEM_DIR}/memory"
  mkdir -p "${GOLEM_DIR}/retrospectives"
fi

# 하위 source에서 덮어쓰지 않도록 export
export GOLEM_DIR GOLEM_PROJECT

source "${GOLEM_ROOT}/lib/soul-parser.sh"
source "${GOLEM_ROOT}/lib/growth-log.sh"
source "${GOLEM_ROOT}/lib/rank-system.sh"

# Lazy module loader — sources a module only if not already loaded
_load() {
  local mod="$1"
  local mod_var="_LOADED_${mod//-/_}"
  mod_var="${mod_var//./_}"
  eval "[ \"\${${mod_var}:-}\" = 1 ] && return 0"
  source "${GOLEM_ROOT}/lib/${mod}" || { echo "[ERROR] Failed to load module: ${mod}" >&2; return 1; }
  eval "${mod_var}=1"
}

# 도움말
usage() {
  cat <<EOF
GolemGarden — AI 에이전트 육성 시스템

Usage: forge <command> [args...]

Project Init:
  init                프로젝트 초기화 안내 (Claude Code에서는 forge-init 사용)
  init fullstack      풀스택 팩 바로 설치
  init gamedev        게임 개발 팩 바로 설치
  init trading        트레이딩 팩 바로 설치

Commands:
  run <name> <task> [session_id]
                      엔진 네이티브 SOUL 소환 (OMC 비의존, claude CLI 직접 호출)
  doctor [--verbose]  엔진 헬스체크 (claude CLI·SOUL·.golem·의존성 진단)
  verify <target> [reviewer] | --tests-only
                      전용 검증 레인 (결정론 테스트 + verifier SOUL, author≠verifier)
  explore <query> [path] | --files <query> [path]
                      grep-우선 코드 컨텍스트 (관련 코드 한 번에 번들)
  overview (ov)       통합 대시보드 — 팀 전체를 한눈에
  status              팀 상태 + SOUL 랭크 확인
  souls               등록된 SOUL 목록
  prompt <name> <task> SOUL 프롬프트 생성 (디버그용)
  rank <name>         SOUL 랭크 확인 + 승급 체크
  promote <name>      SOUL 랭크 승급 실행
  log <name>          SOUL 성장 기록 조회
  log-add <name> <task> <result> [files] [tests]
  log-add-usage <name> <task> <result> <files> <tests> <model> <total_tokens> <duration_ms>
                      Agent usage 기반 자동 비용 계산 후 기록
                      성장 기록 수동 추가
  dashboard           성장 대시보드
  rank-board          랭크 대시보드

Review:
  review <worker> [reviewer] [target]
                      크로스 리뷰 실행
  review-record <worker> <reviewer> <target> <result> [issues] [severity]
                      리뷰 결과 기록
  review-auto <worker> <task>
                      자동 리뷰 트리거 (rank 기반)
  review-status       리뷰 상태 대시보드

SOUL Creation:
  soul-create <role> [name] [model]
                      프리셋 기반 SOUL 생성
  soul-custom <name> <role> <specialties> [personality] [model]
                      커스텀 SOUL 직접 생성
  soul-presets        프리셋 목록 조회
  soul-create-all     전체 프리셋 한번에 생성

Domain Packs:
  pack list           도메인 팩 목록
  pack install <name> 팩 설치 (SOULs + forge-board)
  pack uninstall <name> 팩 제거
  pack info <name>    팩 상세 정보

Knowledge Sync:
  sync status           지식 승격 현황 대시보드
  sync pending          승격 대기열 조회
  sync history          심사 히스토리
  sync record <soul> <learning> <scope> <confidence>
                        학습 수동 기록
  sync-judge <번호> <promote|hold|reject> [사유]
                        심사 판정 (수동)
  sync-promote <soul> <learning>
                        글로벌 SOUL에 지식 반영

Mailbox (SOUL 간 통신):
  mailbox dashboard   메일박스 현황 대시보드
  mailbox send <from> <to> <type> <content>
                      메시지 전송
  mailbox broadcast <from> <content>
                      전체 공지
  mailbox read <soul>  미읽음 메시지 읽기
  mailbox inbox <soul> 전체 수신함 조회
  mailbox cleanup [days]
                      오래된 메시지 정리 (기본 30일)

Session (세션 지속성):
  session create <task> <souls_csv>
                      새 세션 생성
  session status      현재 세션 상태
  session list        전체 세션 목록
  session resume      마지막 세션 재개
  session end [status]
                      세션 종료 (completed|aborted)
  session log <soul> <action> <detail>
                      세션 이벤트 기록

Mission (목표 완수 모드):
  mission init <goal> [criteria] [constraints] [out_of_scope]
                      미션 스펙(spec.md + state.json) 생성, id 반환
  mission set-tasks <id> "<t1>|<t2>|<t3>"
                      파이프 구분 태스크 등록 (체크리스트 + state)
  mission set-tasks-json <id> '<json>'
                      Nex 분해 JSON 등록 — ["t1","t2"] 또는 [{"task":"t1"},...]
  mission run <id> [soul] [verifier_soul]
                      결정론 자율 루프 — execute↔verify 반복, 사이클/재시도 상한·
                      예산 센티널·스턱 디텍터 코드 강제, 완료 시 <promise>COMPLETE</promise>
  mission next <id>   첫 pending 태스크 조회 ('idx<TAB>text', 없으면 none)
  mission task <id> <idx> <pending|in_progress|done|failed> [soul]
                      태스크 상태/담당 SOUL 갱신
  mission status [id] 미션 스펙 + 태스크 진행도 (id 생략 시 최근 active)
  mission list        전체 미션 목록 (진행도 n/m)
  mission complete <id>
                      미션 완료 처리 (mission run 이 검증 통과 시 자동 호출)

Flow (단계 승인 워크플로):
  flow create "<goal>" <steps.json>
                      플로우 생성 → flow_id 출력 + run 안내
  flow run <flow_id> [session_id]
                      상태 검증 후 플로우 실행
  flow status <flow_id>
                      플로우 상태 조회
  flow list           전체 플로우 목록
  flow validate <flow_id>
                      state.json 유효성 검사
  flow approve <flow_id> <step_id>
                      단계 승인
  flow reject <flow_id> <step_id>
                      단계 거부

Studio (프로젝트 독립 플로우 스튜디오 — docs/STUDIO_PLAN.md):
  studio init [dir] [name] [goal]
                      독립 스튜디오 폴더 초기화 (멱등)
  studio design [dir] "goal"
                      AI가 에이전트 팀+플로우 생성 (flowsmith 소환)
  studio redesign [dir] "피드백"
                      기존 팀/플로우 컨텍스트로 flowsmith 재설계
                      (기존 SOUL 유지 + 신규 추가, 항상 새 플로우 생성)
  studio preset list  빌트인 팀 프리셋 목록 (novel-team, market-research 등)
  studio preset apply [dir] preset_id
                      프리셋 팀+플로우 원클릭 적용
  studio agent-add [dir] name model role [rules] [rank] [effort]
                      스튜디오 에이전트 추가
                      (rank: novice|junior|senior|expert|master, effort: low|medium|high)
  studio run [dir] [flow_id]
                      스튜디오 플로우 실행 (기본: 최신 플로우)
  studio status [dir] 스튜디오 요약 (souls/flows)
  studio list          등록된 전체 스튜디오 (GOLEM_ROOT/studios.jsonl)

Recovery (에러 복구):
  recover-history <soul>
                      복구 이력 조회
                      (재시도 실행은 mission run 루프가 담당)

Budget (예산 추적):
  budget status       예산 상태 (토큰/USD/수확체감)
  budget init         예산 초기화
  budget reset        예산 리셋
  budget record <soul> <tokens> [cost]
                      사용량 기록
  budget check        중단 필요 여부 (ok|warning|exceeded|stagnating)

Tool Character (도구 성격):
  tool-char check <tool>
                      도구 성격 조회 (readOnly/concurrent/destructive/idempotent)
  tool-char guide <soul>
                      SOUL 병렬 실행 가이드
  tool-char parallel <soul1> <soul2>
                      두 SOUL 동시 실행 가능 여부

Worktree (격리 실행):
  worktree create <soul> [task]
                      SOUL별 격리 worktree 생성
  worktree merge <soul> [strategy]
                      Worktree 변경사항 머지 (merge|squash|rebase)
  worktree cleanup <soul|all>
                      Worktree 정리
  worktree status     활성 worktree 현황

Portability:
  export <name> <target_dir>
                      SOUL을 다른 프로젝트로 내보내기
  import <source_dir> <name>
                      다른 프로젝트에서 SOUL 가져오기
  export-pack <pack_name> [target_dir]
                      전체 팀을 팩으로 내보내기
  import-pack <pack_dir>
                      SOUL 팩 가져오기
  portability         포터빌리티 상태 대시보드

Insights (성과 분석):
  insights              팀 전체 인사이트
  insights <soul>       SOUL별 성과 패턴 분석

Agent Skills (agentskills.io):
  skill-export <name>   SOUL → Agent Skill 변환
  skill-export --all    전체 SOUL을 Agent Skills로 내보내기
  skill-import <dir>    Agent Skill → SOUL 임포트
  skill-import <parent> --all
                        디렉토리 내 전체 Agent Skills 임포트

Handover (인수인계 자동 생성):
  handover                    M1.5 풀파이프 (--analyze 와 동일)
  handover --analyze          Phase A+B 실행 + 메인 Claude에 Agent 4명 위임
  handover --scan-only        Phase A만 (M1 raw 추출)
  handover --prompts-only     Phase A+B (prompt 생성, Agent 호출은 수동)
  handover --render-only      Phase D만 (HTML 재생성)
  handover --output=DIR       산출물 디렉토리 (기본: ./handover)

Examples:
  forge status
  forge run zen "Reply with one word: PONG"
  forge doctor                          # 엔진 상태 진단
  forge verify --tests-only             # 결정론 테스트만 (무료)
  forge verify "mission_next 구현" zen   # 테스트 + verifier SOUL 판정
  forge explore agent_run               # agent_run 관련 코드 한눈에
  forge explore --files mission_        # 관련 파일 랭크 목록
  forge prompt ryn "인증 API 구현"
  forge rank ryn
  forge log-add ryn "REST API 설계" success 5 12
  forge review ryn zen "AuthController"
  forge review ryn                      # 리뷰어 자동 선정
  forge export ryn /path/to/other/project
  forge import /path/to/source ryn
  forge mission init "결제 모듈 구현" "테스트 통과" "기존 API 유지" "UI 변경"
  forge mission set-tasks msn_... "스키마 설계|핸들러 구현|테스트 작성"
  forge mission status
EOF
}

# 메인 라우터
case "${1:-}" in
  init)
    _load domain-pack.sh
    echo "=== GolemGarden 프로젝트 초기화 ==="
    echo ""
    echo "이 명령은 Claude Code 대화창에서 실행해야 합니다."
    echo "Claude Code에서 다음을 입력하세요:"
    echo ""
    echo '  forge-init'
    echo '  forge-init: 풀스택 웹앱, Spring Boot + React'
    echo ""
    echo "프로젝트를 자동 스캔하고 SOUL 팀을 구성합니다."
    echo ""
    echo "--- 빠른 수동 초기화 ---"
    echo ""
    if [ -n "${2:-}" ]; then
      # 인자가 있으면 팩 설치로 처리
      case "$2" in
        fullstack|풀스택) pack_install fullstack ;;
        gamedev|게임)     pack_install gamedev ;;
        trading|트레이딩)  pack_install trading ;;
        *)
          echo "사용 가능한 팩: fullstack, gamedev, trading"
          echo "또는 개별 SOUL 생성:"
          echo "  forge soul-create backend-developer"
          echo "  forge soul-create frontend-developer"
          echo "  forge soul-create qa-tester"
          ;;
      esac
    else
      echo "현재 등록된 SOUL:"
      soul_list
      echo ""
      echo "팩 설치: forge init fullstack | gamedev | trading"
      echo "개별 생성: forge soul-create <role>"
    fi
    ;;

  run)
    # 엔진 네이티브 SOUL 소환 (OMC 비의존) — lib/agent-runner.sh 의 agent_run
    # forge run <soul> <task> [session_id]
    if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
      echo "Usage: forge run <soul_name> <task> [session_id]"
      exit 1
    fi
    source "${GOLEM_ROOT}/lib/agent-runner.sh"
    agent_run "$2" "$3" "${4:-}"
    exit $?
    ;;

  doctor)
    # 엔진 헬스체크 (omc-doctor 대체) — lib/doctor.sh 의 doctor_run
    # forge doctor [--verbose]
    source "${GOLEM_ROOT}/lib/doctor.sh"
    doctor_run "${2:-}"
    exit $?
    ;;

  verify)
    # 전용 검증 레인 (결정론 테스트 + verifier SOUL) — lib/verify.sh
    # forge verify <target> [verifier_soul]  |  forge verify --tests-only
    source "${GOLEM_ROOT}/lib/verify.sh"
    if [ "${2:-}" = "--tests-only" ]; then
      verify_tests_only
    elif [ -z "${2:-}" ]; then
      echo "Usage: forge verify <target_description> [verifier_soul]"
      echo "       forge verify --tests-only   (결정론 테스트만, SOUL 호출 없음)"
      exit 1
    else
      verify_run "$2" "${3:-}"
    fi
    exit $?
    ;;

  eval)
    # 골든 태스크 스위트 (P2-3) — lib/eval.sh
    # forge eval [--model <m>] [--soul <s>] [--task <id>]
    # forge eval list  |  forge eval report
    source "${GOLEM_ROOT}/lib/eval.sh"
    case "${2:-}" in
      list)   eval_list ;;
      report) eval_report ;;
      *)      shift; eval_run "$@" ;;
    esac
    exit $?
    ;;

  explore)
    # grep-우선 코드 컨텍스트 (CodeGraph 경량판) — lib/explore.sh
    # forge explore <query> [path]  |  forge explore-files <query> [path]
    if [ -z "${2:-}" ]; then
      echo "Usage: forge explore <query> [path]"
      echo "       forge explore --files <query> [path]   (랭크된 파일 목록만)"
      exit 1
    fi
    source "${GOLEM_ROOT}/lib/explore.sh"
    if [ "$2" = "--files" ]; then
      explore_files "${3:-}" "${4:-}"
    else
      explore_run "$2" "${3:-}"
    fi
    exit $?
    ;;

  status)
    echo ""
    soul_list
    echo ""
    growth_log_dashboard
    ;;

  souls)
    soul_list
    ;;

  prompt)
    _load prompt-builder.sh
    if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
      echo "Usage: forge prompt <soul_name> <task>"
      exit 1
    fi
    prompt_build "$2" "$3"
    ;;

  prompt-review)
    _load prompt-builder.sh
    if [ -z "${2:-}" ] || [ -z "${3:-}" ] || [ -z "${4:-}" ]; then
      echo "Usage: forge prompt-review <reviewer> <worker> <target>"
      exit 1
    fi
    prompt_build_review "$2" "$3" "$4"
    ;;

  prompt-director)
    _load prompt-builder.sh
    if [ -z "${2:-}" ]; then
      echo "Usage: forge prompt-director <task>"
      exit 1
    fi
    prompt_build_director "$2"
    ;;

  rank)
    if [ -z "${2:-}" ]; then
      echo "Usage: forge rank <soul_name>"
      exit 1
    fi
    rank_check "$2"
    ;;

  promote)
    _load forge-board.sh
    if [ -z "${2:-}" ]; then
      echo "Usage: forge promote <soul_name>"
      exit 1
    fi
    rank_promote "$2"
    ;;

  log)
    if [ -z "${2:-}" ]; then
      echo "Usage: forge log <soul_name>"
      exit 1
    fi
    growth_log_summary "$2"
    echo ""
    echo "--- 상세 기록 ---"
    cat "${GROWTH_DIR}/${2}.jsonl" 2>/dev/null || echo "(기록 없음)"
    ;;

  log-add)
    if [ -z "${2:-}" ] || [ -z "${3:-}" ] || [ -z "${4:-}" ]; then
      echo "Usage: forge log-add <soul_name> <task> <result> [files_changed] [tests_passed]"
      exit 1
    fi
    growth_log_append "$2" "$3" "$4" "${5:-0}" "${6:-0}"
    # forge-board 태스크 히스토리 업데이트
    _load forge-board.sh
    board_add_task "$(date +%Y-%m-%d)" "$3" "$2" "$4"
    # 자동 승급 시도 (조건 충족 시 실행, 미충족 시 현황 보고)
    rank_promote "$2" 2>/dev/null || rank_check "$2"
    # 자동 업적 체크
    _load achievement.sh
    achievement_check "$2"
    ;;

  log-add-usage)
    # Agent usage 데이터로 자동 비용 계산 후 기록
    # Usage: forge log-add-usage <soul> <task> <result> <files> <tests> <model> <total_tokens> <duration_ms>
    if [ -z "${2:-}" ] || [ -z "${3:-}" ] || [ -z "${4:-}" ] || [ -z "${7:-}" ]; then
      echo "Usage: forge log-add-usage <soul> <task> <result> <files> <tests> <model> <total_tokens> <duration_ms>"
      exit 1
    fi
    _load budget.sh
    _lau_cost_data=$(budget_estimate_cost "${7:-sonnet}" "${8:-0}" "${9:-0}")
    read -r _lau_tin _lau_tout _lau_cost <<< "$_lau_cost_data"
    growth_log_append "$2" "$3" "$4" "${5:-0}" "${6:-0}" "" "" "$_lau_tin" "$_lau_tout" 0 "$_lau_cost" "${7:-sonnet}" "${9:-0}"
    budget_record "$2" "$_lau_tout" "$_lau_cost"
    # forge-board 태스크 히스토리 업데이트
    _load forge-board.sh
    board_add_task "$(date +%Y-%m-%d)" "$3" "$2" "$4" "\$${_lau_cost}"
    # 자동 승급 시도 + 업적 체크
    rank_promote "$2" 2>/dev/null || rank_check "$2"
    _load achievement.sh
    achievement_check "$2"
    ;;

  dashboard)
    case "${2:-}" in
      --cost|cost)
        growth_log_cost_dashboard
        ;;
      --web|web)
        _load dashboard-web.sh
        dashboard_web_generate
        ;;
      refresh)
        _load dashboard-web.sh
        dashboard_web_refresh
        ;;
      serve)
        _load dashboard-web.sh
        dashboard_web_serve "${3:-9470}"
        ;;
      stop)
        _load dashboard-web.sh
        dashboard_web_stop
        ;;
      open)
        _load dashboard-web.sh
        dashboard_web_serve "${3:-9470}"
        ;;
      global)
        _load dashboard-global.sh
        dashboard_global_generate
        ;;
      global-refresh)
        _load dashboard-global.sh
        dashboard_global_refresh
        ;;
      global-serve)
        _load dashboard-global.sh
        dashboard_global_serve "${3:-9471}"
        ;;
      global-stop)
        _load dashboard-global.sh
        dashboard_global_stop
        ;;
      global-projects)
        _load dashboard-global.sh
        dashboard_global_projects
        ;;
      global-register)
        _load dashboard-global.sh
        dashboard_global_register "${3:-}"
        ;;
      global-sync)
        _load global-sync.sh
        global_sync
        ;;
      global-sync-status)
        _load global-sync.sh
        global_sync_status
        ;;
      *)
        growth_log_dashboard
        ;;
    esac
    ;;

  rank-board)
    rank_dashboard
    ;;

  review)
    _load forge-review.sh
    _load prompt-builder.sh
    if [ -z "${2:-}" ]; then
      echo "Usage: forge review <worker> [reviewer] [target]"
      exit 1
    fi
    review_execute "$2" "${3:-}" "${4:-전체 변경사항}"
    ;;

  review-record)
    _load forge-review.sh
    _load forge-board.sh
    if [ -z "${2:-}" ] || [ -z "${3:-}" ] || [ -z "${4:-}" ] || [ -z "${5:-}" ]; then
      echo "Usage: forge review-record <worker> <reviewer> <target> <result> [issues] [severity]"
      exit 1
    fi
    review_record "$2" "$3" "$4" "$5" "${6:-0}" "${7:-none}"
    ;;

  review-auto)
    _load forge-review.sh
    _load prompt-builder.sh
    if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
      echo "Usage: forge review-auto <worker> <task>"
      exit 1
    fi
    review_auto_trigger "$2" "$3"
    ;;

  review-status)
    _load forge-review.sh
    review_status
    ;;

  export)
    _load portability.sh
    if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
      echo "Usage: forge export <soul_name> <target_dir>"
      exit 1
    fi
    soul_export "$2" "$3"
    ;;

  import)
    _load portability.sh
    if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
      echo "Usage: forge import <source_dir> <soul_name>"
      exit 1
    fi
    soul_import "$2" "$3"
    ;;

  export-pack)
    _load portability.sh
    if [ -z "${2:-}" ]; then
      echo "Usage: forge export-pack <pack_name> [target_dir]"
      exit 1
    fi
    soul_export_pack "$2" "${3:-.}"
    ;;

  import-pack)
    _load portability.sh
    if [ -z "${2:-}" ]; then
      echo "Usage: forge import-pack <pack_dir>"
      exit 1
    fi
    soul_import_pack "$2"
    ;;

  sync)
    _load knowledge-sync.sh
    case "${2:-}" in
      status)
        knowledge_dashboard
        ;;
      pending)
        knowledge_pending
        ;;
      history)
        knowledge_history
        ;;
      record)
        if [ -z "${3:-}" ] || [ -z "${4:-}" ]; then
          echo "Usage: forge sync record <soul> <learning> [scope] [confidence]"
          exit 1
        fi
        knowledge_record "$3" "$4" "${5:-universal}" "${6:-medium}" "${7:-}"
        ;;
      *)
        knowledge_dashboard
        ;;
    esac
    ;;

  sync-judge)
    _load knowledge-sync.sh
    if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
      echo "Usage: forge sync-judge <번호> <promote|hold|reject> [사유]"
      exit 1
    fi
    knowledge_judge "$2" "$3" "${4:-}"
    ;;

  sync-promote)
    _load knowledge-sync.sh
    if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
      echo "Usage: forge sync-promote <soul> <learning>"
      exit 1
    fi
    knowledge_promote "$2" "$3"
    ;;

  portability)
    _load portability.sh
    portability_status
    ;;

  mailbox)
    _load mailbox.sh
    case "${2:-}" in
      dashboard|"")
        mailbox_dashboard
        ;;
      send)
        if [ -z "${3:-}" ] || [ -z "${4:-}" ] || [ -z "${5:-}" ] || [ -z "${6:-}" ]; then
          echo "Usage: forge mailbox send <from> <to> <type> <content>"
          exit 1
        fi
        mailbox_send "$3" "$4" "$5" "$6"
        ;;
      broadcast)
        if [ -z "${3:-}" ] || [ -z "${4:-}" ]; then
          echo "Usage: forge mailbox broadcast <from> <content>"
          exit 1
        fi
        mailbox_broadcast "$3" "$4"
        ;;
      read)
        if [ -z "${3:-}" ]; then
          echo "Usage: forge mailbox read <soul_name>"
          exit 1
        fi
        mailbox_read "$3"
        ;;
      inbox)
        if [ -z "${3:-}" ]; then
          echo "Usage: forge mailbox inbox <soul_name>"
          exit 1
        fi
        mailbox_inbox "$3"
        ;;
      cleanup)
        mailbox_cleanup "${3:-30}"
        ;;
      init)
        mailbox_init
        ;;
      *)
        echo "Usage: forge mailbox <dashboard|send|broadcast|read|inbox|cleanup|init>"
        exit 1
        ;;
    esac
    ;;

  session)
    _load session.sh
    case "${2:-}" in
      create)
        if [ -z "${3:-}" ] || [ -z "${4:-}" ]; then
          echo "Usage: forge session create <task> <souls_csv>"
          exit 1
        fi
        session_create "$3" "$4"
        ;;
      status|"")
        session_status
        ;;
      list)
        session_list
        ;;
      resume)
        session_resume
        ;;
      end)
        session_end "${3:-completed}"
        ;;
      log)
        if [ -z "${3:-}" ] || [ -z "${4:-}" ] || [ -z "${5:-}" ]; then
          echo "Usage: forge session log <soul> <action> <detail>"
          exit 1
        fi
        session_log "$3" "$4" "$5"
        ;;
      fork)
        if [ -z "${3:-}" ]; then
          echo "Usage: forge session fork <session_id>"
          exit 1
        fi
        session_fork "$3"
        ;;
      branch)
        session_branch
        ;;
      tree)
        session_tree
        ;;
      *)
        echo "Usage: forge session <create|status|list|resume|end|log|fork|branch|tree>"
        exit 1
        ;;
    esac
    ;;

  mission)
    _load mission.sh
    case "${2:-}" in
      init)
        if [ -z "${3:-}" ]; then
          echo "Usage: forge mission init <goal> [criteria] [constraints] [out_of_scope]"
          exit 1
        fi
        mission_init "$3" "${4:-}" "${5:-}" "${6:-}"
        ;;
      set-tasks)
        if [ -z "${3:-}" ] || [ -z "${4:-}" ]; then
          echo "Usage: forge mission set-tasks <id> \"<t1>|<t2>|<t3>\""
          exit 1
        fi
        mission_set_tasks "$3" "$4"
        ;;
      set-tasks-json)
        if [ -z "${3:-}" ] || [ -z "${4:-}" ]; then
          echo "Usage: forge mission set-tasks-json <id> '<json_array_or_file>'"
          exit 1
        fi
        mission_set_tasks_json "$3" "$4"
        ;;
      task)
        if [ -z "${3:-}" ] || [ -z "${4:-}" ] || [ -z "${5:-}" ]; then
          echo "Usage: forge mission task <id> <idx> <pending|in_progress|done|failed> [soul]"
          exit 1
        fi
        mission_task "$3" "$4" "$5" "${6:-}"
        ;;
      status)
        mission_status "${3:-}"
        ;;
      list)
        mission_list
        ;;
      complete)
        if [ -z "${3:-}" ]; then
          echo "Usage: forge mission complete <id>"
          exit 1
        fi
        mission_complete "$3"
        ;;
      next)
        if [ -z "${3:-}" ]; then
          echo "Usage: forge mission next <id>"
          exit 1
        fi
        mission_next "$3"
        ;;
      run)
        _load mission-loop.sh
        if [ -z "${3:-}" ]; then
          echo "Usage: forge mission run <id> [soul] [verifier_soul]"
          exit 1
        fi
        mission_run "$3" "${4:-}" "${5:-}"
        exit $?
        ;;
      *)
        echo "Usage: forge mission <init|set-tasks|task|status|list|complete|next|run>"
        exit 1
        ;;
    esac
    ;;

  flow)
    _load flow.sh
    case "${2:-}" in
      create)
        if [ -z "${3:-}" ] || [ -z "${4:-}" ]; then
          echo "Usage: forge flow create \"<goal>\" <steps.json>"
          exit 1
        fi
        _flow_id=$(flow_create "$3" "$4")
        echo "Flow 생성: ${_flow_id}"
        echo "실행: forge flow run ${_flow_id}"
        ;;
      run)
        if [ -z "${3:-}" ]; then
          echo "Usage: forge flow run <flow_id>"
          exit 1
        fi
        flow_validate "${GOLEM_DIR}/flows/${3}/state.json" && flow_run "$3"
        exit $?
        ;;
      status)
        if [ -z "${3:-}" ]; then
          echo "Usage: forge flow status <flow_id>"
          exit 1
        fi
        flow_status "$3"
        ;;
      list)
        flow_list
        ;;
      validate)
        if [ -z "${3:-}" ]; then
          echo "Usage: forge flow validate <flow_id>"
          exit 1
        fi
        flow_validate "${GOLEM_DIR}/flows/${3}/state.json"
        ;;
      approve)
        if [ -z "${3:-}" ] || [ -z "${4:-}" ]; then
          echo "Usage: forge flow approve <flow_id> <step_id>"
          exit 1
        fi
        flow_approve "$3" "$4"
        ;;
      reject)
        if [ -z "${3:-}" ] || [ -z "${4:-}" ]; then
          echo "Usage: forge flow reject <flow_id> <step_id>"
          exit 1
        fi
        flow_reject "$3" "$4"
        ;;
      *)
        echo "Usage: forge flow <create|run|status|list|validate|approve|reject>"
        exit 1
        ;;
    esac
    ;;

  studio)
    _load studio.sh
    case "${2:-}" in
      init)
        studio_init "${3:-}" "${4:-}" "${5:-}"
        exit $?
        ;;
      design)
        # [dir] 생략 가능 — 게이트웨이는 cwd=스튜디오 + GOLEM_PROJECT 로 goal 만 보낸다
        if [ -z "${3:-}" ]; then
          echo "Usage: forge studio design [dir] \"<goal>\""
          exit 1
        fi
        if [ -n "${4:-}" ]; then
          studio_design "$3" "$4"
        else
          studio_design "$3"
        fi
        exit $?
        ;;
      agent-add)
        if [ -z "${3:-}" ] || [ -z "${4:-}" ]; then
          echo "Usage: forge studio agent-add [dir] <name> <model> <role> [rules] [rank] [effort]"
          exit 1
        fi
        studio_agent_add "$3" "$4" "${5:-}" "${6:-}" "${7:-}" "${8:-}" "${9:-}"
        exit $?
        ;;
      redesign)
        # [dir] 생략 가능 — 단일 인자는 피드백 (design 과 동일 규약)
        if [ -z "${3:-}" ]; then
          echo "Usage: forge studio redesign [dir] \"<피드백>\""
          exit 1
        fi
        if [ -n "${4:-}" ]; then
          studio_redesign "$3" "$4"
        else
          studio_redesign "$3"
        fi
        exit $?
        ;;
      preset)
        case "${3:-}" in
          list)
            studio_preset_list
            exit $?
            ;;
          apply)
            if [ -z "${4:-}" ]; then
              echo "Usage: forge studio preset apply [dir] <preset_id>"
              exit 1
            fi
            if [ -n "${5:-}" ]; then
              studio_preset_apply "$4" "$5"
            else
              studio_preset_apply "$4"
            fi
            exit $?
            ;;
          *)
            echo "Usage: forge studio preset <list|apply>"
            exit 1
            ;;
        esac
        ;;
      run)
        studio_run "${3:-}" "${4:-}"
        exit $?
        ;;
      status)
        studio_status "${3:-}"
        exit $?
        ;;
      list)
        studio_list
        exit $?
        ;;
      *)
        echo "Usage: forge studio <init|design|redesign|preset|agent-add|run|status|list>"
        exit 1
        ;;
    esac
    ;;

  recover-history)
    _load error-recovery.sh
    if [ -z "${2:-}" ]; then
      echo "Usage: forge recover-history <soul_name>"
      exit 1
    fi
    error_history "$2"
    ;;

  cost-dashboard)
    growth_log_cost_dashboard
    ;;

  sync-global)
    _load global-sync.sh
    global_sync
    ;;

  sync-global-status)
    _load global-sync.sh
    global_sync_status
    ;;

  budget)
    _load budget.sh
    case "${2:-}" in
      init)     budget_init ;;
      reset)    budget_reset ;;
      record)
        if [ -z "${3:-}" ] || [ -z "${4:-}" ]; then
          echo "Usage: forge budget record <soul> <tokens_out> [cost_usd]"
          exit 1
        fi
        budget_record "$3" "$4" "${5:-0.000}"
        ;;
      check)    budget_check ;;
      status|"") budget_status ;;
      *)
        echo "Usage: forge budget <init|reset|record|check|status>"
        exit 1
        ;;
    esac
    ;;

  tool-char)
    _load tool-character.sh
    case "${2:-}" in
      check)
        if [ -z "${3:-}" ]; then
          echo "Usage: forge tool-char check <tool_name>"
          exit 1
        fi
        _tc_char=$(tool_get_character "$3")
        echo "$3: readOnly=$(echo $_tc_char | awk '{print $1}') concurrent=$(echo $_tc_char | awk '{print $2}') destructive=$(echo $_tc_char | awk '{print $3}') idempotent=$(echo $_tc_char | awk '{print $4}')"
        ;;
      guide)
        if [ -z "${3:-}" ]; then
          echo "Usage: forge tool-char guide <soul_name>"
          exit 1
        fi
        soul_concurrency_guide "$3"
        ;;
      parallel)
        if [ -z "${3:-}" ] || [ -z "${4:-}" ]; then
          echo "Usage: forge tool-char parallel <soul1> <soul2>"
          exit 1
        fi
        _tc_result=$(can_run_parallel "$3" "$4")
        echo "${3} + ${4}: ${_tc_result}"
        ;;
      *)
        echo "Usage: forge tool-char <check|guide|parallel>"
        exit 1
        ;;
    esac
    ;;

  worktree)
    _load worktree.sh
    case "${2:-}" in
      create)
        if [ -z "${3:-}" ]; then
          echo "Usage: forge worktree create <soul_name> [task]"
          exit 1
        fi
        forge_worktree_create "$3" "${4:-work}"
        ;;
      merge)
        if [ -z "${3:-}" ]; then
          echo "Usage: forge worktree merge <soul_name> [strategy]"
          exit 1
        fi
        forge_worktree_merge "$3" "${4:-merge}"
        ;;
      cleanup)
        if [ -z "${3:-}" ]; then
          echo "Usage: forge worktree cleanup <soul_name|all>"
          exit 1
        fi
        forge_worktree_cleanup "$3"
        ;;
      status|"")
        forge_worktree_status
        ;;
      *)
        echo "Usage: forge worktree <create|merge|cleanup|status>"
        exit 1
        ;;
    esac
    ;;

  memory)
    _load soul-memory.sh
    case "${2:-}" in
      record)
        if [ -z "${3:-}" ] || [ -z "${4:-}" ] || [ -z "${5:-}" ]; then
          echo "Usage: forge memory record <soul> <task_context> <lesson> [tags]"
          exit 1
        fi
        memory_record "$3" "$4" "$5" "${6:-}"
        ;;
      recall)
        if [ -z "${3:-}" ] || [ -z "${4:-}" ]; then
          echo "Usage: forge memory recall <soul> <keywords>"
          exit 1
        fi
        memory_recall "$3" "$4"
        ;;
      list)
        if [ -z "${3:-}" ]; then
          echo "Usage: forge memory list <soul>"
          exit 1
        fi
        memory_list "$3"
        ;;
      forget)
        if [ -z "${3:-}" ] || [ -z "${4:-}" ]; then
          echo "Usage: forge memory forget <soul> <line_number>"
          exit 1
        fi
        memory_forget "$3" "$4"
        ;;
      dashboard|"")
        memory_dashboard
        ;;
      *)
        echo "Usage: forge memory <record|recall|list|forget|dashboard>"
        exit 1
        ;;
    esac
    ;;

  retro)
    _load retrospective.sh
    case "${2:-}" in
      generate)
        if [ -z "${3:-}" ] || [ -z "${4:-}" ]; then
          echo "Usage: forge retro generate <task> <souls_csv>"
          exit 1
        fi
        retro_generate "$3" "$4"
        ;;
      list)
        retro_list
        ;;
      latest)
        retro_latest
        ;;
      trend)
        retro_trend
        ;;
      *)
        echo "Usage: forge retro <generate|list|latest|trend>"
        exit 1
        ;;
    esac
    ;;

  chemistry)
    _load chemistry.sh
    case "${2:-}" in
      record)
        if [ -z "${3:-}" ] || [ -z "${4:-}" ] || [ -z "${5:-}" ] || [ -z "${6:-}" ]; then
          echo "Usage: forge chemistry record <soul1> <soul2> <type> <result> [detail]"
          exit 1
        fi
        chemistry_record "$3" "$4" "$5" "$6" "${7:-}"
        ;;
      score)
        if [ -z "${3:-}" ] || [ -z "${4:-}" ]; then
          echo "Usage: forge chemistry score <soul1> <soul2>"
          exit 1
        fi
        echo "$(chemistry_score "$3" "$4")"
        ;;
      best)
        if [ -z "${3:-}" ]; then
          echo "Usage: forge chemistry best <soul>"
          exit 1
        fi
        chemistry_best_partner "$3"
        ;;
      matrix)
        if [ -z "${3:-}" ]; then
          echo "Usage: forge chemistry matrix <souls_csv>"
          exit 1
        fi
        chemistry_team_recommend "$3"
        ;;
      dashboard|"")
        chemistry_dashboard
        ;;
      *)
        echo "Usage: forge chemistry <record|score|best|matrix|dashboard>"
        exit 1
        ;;
    esac
    ;;

  achievement|achievements)
    _load achievement.sh
    case "${2:-}" in
      check)
        if [ -z "${3:-}" ]; then
          echo "Usage: forge achievement check <soul>"
          exit 1
        fi
        achievement_check "$3"
        ;;
      list)
        if [ -z "${3:-}" ]; then
          echo "Usage: forge achievement list <soul>"
          exit 1
        fi
        achievement_list "$3"
        ;;
      dashboard|"")
        achievement_dashboard
        ;;
      *)
        echo "Usage: forge achievement <check|list|dashboard>"
        exit 1
        ;;
    esac
    ;;

  skill-tree)
    _load skill-tree.sh
    case "${2:-}" in
      branches)
        if [ -z "${3:-}" ]; then
          echo "Usage: forge skill-tree branches <role>"
          exit 1
        fi
        skill_tree_branches "$3"
        ;;
      specialize)
        if [ -z "${3:-}" ] || [ -z "${4:-}" ]; then
          echo "Usage: forge skill-tree specialize <soul> <branch>"
          exit 1
        fi
        skill_tree_specialize "$3" "$4"
        ;;
      respec)
        if [ -z "${3:-}" ] || [ -z "${4:-}" ]; then
          echo "Usage: forge skill-tree respec <soul> <new_branch>"
          exit 1
        fi
        skill_tree_respec "$3" "$4"
        ;;
      current)
        if [ -z "${3:-}" ]; then
          echo "Usage: forge skill-tree current <soul>"
          exit 1
        fi
        skill_tree_current "$3"
        ;;
      dashboard|"")
        skill_tree_dashboard
        ;;
      *)
        echo "Usage: forge skill-tree <branches|specialize|respec|current|dashboard>"
        exit 1
        ;;
    esac
    ;;

  dna)
    _load project-dna.sh
    case "${2:-}" in
      generate)
        dna_generate "${3:-}" "${4:-}" "${5:-}" "${6:-}" "${7:-}"
        ;;
      show|"")
        dna_show
        ;;
      compare)
        if [ -z "${3:-}" ]; then
          echo "Usage: forge dna compare <other_dna_file>"
          exit 1
        fi
        dna_compare "$3"
        ;;
      adapt)
        if [ -z "${3:-}" ] || [ -z "${4:-}" ]; then
          echo "Usage: forge dna adapt <soul> <source_dna_file>"
          exit 1
        fi
        dna_adaptation_guide "$3" "$4"
        ;;
      *)
        echo "Usage: forge dna <generate|show|compare|adapt>"
        exit 1
        ;;
    esac
    ;;

  soul-create)
    _load forge-soul.sh
    if [ -z "${2:-}" ]; then
      echo "Usage: forge soul-create <role> [name] [model]"
      echo "Roles: backend-developer, frontend-developer, devops-engineer, qa-tester, data-analyst, technical-writer, security-auditor"
      exit 1
    fi
    soul_create_from_preset "$2" "${3:-}" "${4:-sonnet}"
    ;;

  soul-custom)
    _load forge-soul.sh
    if [ -z "${2:-}" ] || [ -z "${3:-}" ] || [ -z "${4:-}" ]; then
      echo "Usage: forge soul-custom <name> <role> <specialties> [personality] [model]"
      exit 1
    fi
    soul_create_custom "$2" "$3" "$4" "${5:-}" "${6:-sonnet}"
    ;;

  soul-presets)
    _load forge-soul.sh
    soul_preset_list
    ;;

  soul-create-all)
    _load forge-soul.sh
    soul_create_all_presets
    ;;

  pack)
    _load domain-pack.sh
    case "${2:-}" in
      list)
        pack_list
        ;;
      install)
        if [ -z "${3:-}" ]; then
          echo "Usage: forge pack install <pack_name>"
          exit 1
        fi
        pack_install "$3"
        ;;
      uninstall)
        if [ -z "${3:-}" ]; then
          echo "Usage: forge pack uninstall <pack_name>"
          exit 1
        fi
        pack_uninstall "$3"
        ;;
      info)
        if [ -z "${3:-}" ]; then
          echo "Usage: forge pack info <pack_name>"
          exit 1
        fi
        pack_info "$3"
        ;;
      *)
        echo "Usage: forge pack <list|install|uninstall|info> [name]"
        exit 1
        ;;
    esac
    ;;

  overview|ov)
    _load dashboard-unified.sh
    dashboard_unified
    ;;

  insights)
    _load insights.sh
    insights_main "${2:-team}"
    ;;

  skill-export)
    _load soul-to-skill.sh
    if [ -z "${2:-}" ]; then
      echo "Usage: forge skill-export <soul_name|--all> [output-dir]"
      exit 1
    fi
    if [ "$2" = "--all" ]; then
      soul_to_skill_main "--all" "${3:-${GOLEM_ROOT}/dist/skills}"
    else
      soul_to_skill_main "$2" "${3:-${GOLEM_ROOT}/dist/skills}"
    fi
    ;;

  skill-import)
    _load skill-to-soul.sh
    if [ -z "${2:-}" ]; then
      echo "Usage: forge skill-import <skill-dir> [--all] [output-dir]"
      exit 1
    fi
    if [ "${3:-}" = "--all" ]; then
      skill_to_soul_main "$2" "--all" "${4:-${GOLEM_DIR}/souls}"
    else
      skill_to_soul_main "$2" "${3:-${GOLEM_DIR}/souls}"
    fi
    ;;

  handover)
    HANDOVER_OUTPUT_DIR="${GOLEM_PROJECT}/handover"
    HANDOVER_MODE="analyze"  # 기본: M1.5 풀파이프
    HANDOVER_NO_INTERVIEW=0
    shift
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --no-interview) HANDOVER_NO_INTERVIEW=1; shift ;;
        --output=*)     HANDOVER_OUTPUT_DIR="${1#--output=}"; shift ;;
        --output)       HANDOVER_OUTPUT_DIR="$2"; shift 2 ;;
        --analyze)        HANDOVER_MODE="analyze"; shift ;;
        --scan-only)      HANDOVER_MODE="scan"; shift ;;
        --prompts-only)   HANDOVER_MODE="prompts"; shift ;;
        --render-only)    HANDOVER_MODE="render"; shift ;;
        --interview)      HANDOVER_MODE="interview"; shift ;;
        --with-interview) HANDOVER_MODE="with_interview"; shift ;;
        -h|--help)
          cat <<'HELP'
Usage: forge handover [MODE] [--output=DIR] [--no-interview]

  자동 인수인계 자료 생성 (단일 HTML + MD 부산물)

Modes:
  (default)        --analyze 와 동일 (M1.5 풀파이프)
  --analyze        Phase A→B 실행 + 메인 Claude에게 4 Agent 병렬 소환 위임 (M1.5)
  --scan-only      Phase A만 — raw 추출만 (M1 동작)
  --prompts-only   Phase A+B — prompt 생성까지 (사용자가 Agent 호출)
  --render-only    Phase D만 — 기존 src/*.md로 HTML 재생성
  --interview      Phase E만 — 인터뷰 prompt 생성 (메인 Claude가 AskUserQuestion 수행)
  --with-interview M2 풀파이프 — A+B+(C 위임)+D+E+(F+D 위임)

Options:
  --output=DIR     산출물 디렉토리 (기본: ./handover)
  --no-interview   (M2 이후) 인터뷰 단계 스킵

Output:
  DIR/src/00~07-*.md      raw 또는 분석본 (모드별)
  DIR/.prompts/*.md       SOUL prompt 4개 (--analyze, --prompts-only)
  DIR/ONBOARDING.html     단일 HTML (--render-only 또는 --analyze 후속)
HELP
          exit 0 ;;
        *)
          echo "[handover] 알 수 없는 인자: $1" >&2
          exit 1 ;;
      esac
    done

    # Python 인터프리터 탐색 (render 단계에서 필요)
    HANDOVER_PYTHON_CMD=""
    for cand in python python3 py; do
      if command -v "$cand" >/dev/null 2>&1; then
        if "$cand" -c "import sys; sys.exit(0 if sys.version_info[0]>=3 else 1)" >/dev/null 2>&1; then
          HANDOVER_PYTHON_CMD="$cand"; break
        fi
      fi
    done

    mkdir -p "${HANDOVER_OUTPUT_DIR}/src"

    # Phase A — scan (--scan-only, --prompts-only, --analyze)
    if [ "$HANDOVER_MODE" = "scan" ] || [ "$HANDOVER_MODE" = "prompts" ] || [ "$HANDOVER_MODE" = "analyze" ]; then
      echo "=== forge handover (mode: ${HANDOVER_MODE}) ==="
      echo "[Phase A] 자동 추출 (handover-scan.sh)"
      if ! bash "${GOLEM_ROOT}/lib/handover-scan.sh" "${GOLEM_PROJECT}" "${HANDOVER_OUTPUT_DIR}/src"; then
        echo "[handover][ERROR] Phase A 실패." >&2
        exit 1
      fi
      if [ "$HANDOVER_MODE" = "scan" ]; then
        echo ""
        echo "[OK] raw 추출 완료. 분석은 'forge handover --analyze' 또는 'forge handover'."
        exit 0
      fi
    fi

    # Phase B — analyze prompts (--prompts-only, --analyze)
    if [ "$HANDOVER_MODE" = "prompts" ] || [ "$HANDOVER_MODE" = "analyze" ]; then
      echo "[Phase B] 분석 prompt 생성 (handover-analyze.sh)"
      if ! bash "${GOLEM_ROOT}/lib/handover-analyze.sh" "${HANDOVER_OUTPUT_DIR}"; then
        echo "[handover][ERROR] Phase B 실패." >&2
        exit 1
      fi
      echo ""
      echo "=============================================================="
      if [ "$HANDOVER_MODE" = "prompts" ]; then
        echo "[handover-analyze] Phase B 완료 — prompt 4개 생성됨"
        echo "=============================================================="
        echo "Phase C는 사용자 또는 메인 Claude가 수동 수행:"
      else
        echo "[handover-analyze] Phase B 완료 — 메인 Claude에게 위임"
        echo "=============================================================="
        echo "Phase C: Agent 4개 병렬 소환 필요 (메인 Claude 컨텍스트가 수행)"
      fi
      echo ""
      echo "  Agent #1: ${HANDOVER_OUTPUT_DIR}/.prompts/00-nex.md  → 텍스트 출력 → ${HANDOVER_OUTPUT_DIR}/src/00-overview.md 저장"
      echo "  Agent #2: ${HANDOVER_OUTPUT_DIR}/.prompts/01-ryn.md  → ${HANDOVER_OUTPUT_DIR}/src/01-architecture.md 직접 Write"
      echo "  Agent #3: ${HANDOVER_OUTPUT_DIR}/.prompts/02-sage.md → ${HANDOVER_OUTPUT_DIR}/src/02-directory.md 직접 Write"
      echo "  Agent #4: ${HANDOVER_OUTPUT_DIR}/.prompts/03-bolt.md → ${HANDOVER_OUTPUT_DIR}/src/03-dev-guide.md 직접 Write"
      echo ""
      echo "Phase C 완료 후 'forge handover --render-only' 를 실행해 HTML 빌드."
      echo "=============================================================="
      exit 0
    fi

    # Phase D — render only
    if [ "$HANDOVER_MODE" = "render" ] || [ "$HANDOVER_MODE" = "analyze_full_unused" ]; then
      if [ -z "$HANDOVER_PYTHON_CMD" ]; then
        echo "[handover][ERROR] Python 3 인터프리터를 찾을 수 없습니다." >&2
        exit 1
      fi
      echo "[Phase D] HTML 빌드 (handover-render.py, python=${HANDOVER_PYTHON_CMD})"
      if ! GOLEM_PROJECT="${GOLEM_PROJECT}" "$HANDOVER_PYTHON_CMD" "${GOLEM_ROOT}/lib/handover-render.py" "${HANDOVER_OUTPUT_DIR}/src" "${HANDOVER_OUTPUT_DIR}/ONBOARDING.html"; then
        echo "[handover][ERROR] HTML 렌더링 실패. markdown 라이브러리 확인:" >&2
        echo "  ${HANDOVER_PYTHON_CMD} -m pip install markdown" >&2
        exit 1
      fi
      echo ""
      echo "[OK] 인수인계 자료 생성 완료"
      echo "  HTML:  ${HANDOVER_OUTPUT_DIR}/ONBOARDING.html"
      echo "  부산물: ${HANDOVER_OUTPUT_DIR}/src/"
      exit 0
    fi

    # Phase E — interview (--interview, --with-interview 모드에서)
    if [ "$HANDOVER_MODE" = "interview" ] || [ "$HANDOVER_MODE" = "with_interview" ]; then
      # with_interview: Phase A + B 먼저 실행
      if [ "$HANDOVER_MODE" = "with_interview" ]; then
        echo "=== forge handover (mode: with_interview) ==="
        echo "[Phase A] 자동 추출 (handover-scan.sh)"
        if ! bash "${GOLEM_ROOT}/lib/handover-scan.sh" "${GOLEM_PROJECT}" "${HANDOVER_OUTPUT_DIR}/src"; then
          echo "[handover][ERROR] Phase A 실패." >&2
          exit 1
        fi
        echo "[Phase B] 분석 prompt 생성 (handover-analyze.sh)"
        if ! bash "${GOLEM_ROOT}/lib/handover-analyze.sh" "${HANDOVER_OUTPUT_DIR}"; then
          echo "[handover][ERROR] Phase B 실패." >&2
          exit 1
        fi
      fi

      # src/*.md 존재 확인
      if [ ! -f "${HANDOVER_OUTPUT_DIR}/src/04-pitfalls.md" ] || [ ! -f "${HANDOVER_OUTPUT_DIR}/src/06-glossary.md" ]; then
        echo "[handover][ERROR] handover/src/ 없음. 먼저 'forge handover --scan-only' 실행." >&2
        exit 1
      fi

      echo "[Phase E] 인터뷰 prompt 준비 (handover-interview.sh)"
      if ! bash "${GOLEM_ROOT}/lib/handover-interview.sh" "${HANDOVER_OUTPUT_DIR}"; then
        echo "[handover][ERROR] Phase E 실패." >&2
        exit 1
      fi

      if [ "$HANDOVER_MODE" = "with_interview" ]; then
        echo ""
        echo "=================================================================="
        echo "[handover --with-interview] Bash 단계 완료 — 메인 Claude에게 위임"
        echo "=================================================================="
        echo ""
        echo "다음을 순차 수행:"
        echo ""
        echo "  1. (Phase C) Agent 4개 병렬 소환:"
        echo "     - ${HANDOVER_OUTPUT_DIR}/.prompts/00-nex.md  → ${HANDOVER_OUTPUT_DIR}/src/00-overview.md (architect, opus)"
        echo "     - ${HANDOVER_OUTPUT_DIR}/.prompts/01-ryn.md  → ${HANDOVER_OUTPUT_DIR}/src/01-architecture.md (executor, sonnet)"
        echo "     - ${HANDOVER_OUTPUT_DIR}/.prompts/02-sage.md → ${HANDOVER_OUTPUT_DIR}/src/02-directory.md (executor, opus)"
        echo "     - ${HANDOVER_OUTPUT_DIR}/.prompts/03-bolt.md → ${HANDOVER_OUTPUT_DIR}/src/03-dev-guide.md (executor, sonnet)"
        echo ""
        echo "  2. (Phase D) bash forge.sh handover --render-only"
        echo ""
        echo "  3. (Phase F) AskUserQuestion 4 라운드:"
        echo "     - ${HANDOVER_OUTPUT_DIR}/.questions/questions.md Read 후 4 라운드 진행"
        echo "     - 답변을 ${HANDOVER_OUTPUT_DIR}/.interview/answers.md 에 누적"
        echo "     - ${HANDOVER_OUTPUT_DIR}/src/04-pitfalls.md, 06-glossary.md 새로 Write"
        echo ""
        echo "  4. (Phase D 재실행) bash forge.sh handover --render-only"
        echo ""
        echo "=================================================================="
      else
        echo ""
        echo "[OK] Phase E 완료. 메인 Claude가 AskUserQuestion 4 라운드를 수행하고"
        echo "     답변을 ${HANDOVER_OUTPUT_DIR}/.interview/answers.md 에 누적한 후"
        echo "     'forge handover --render-only' 로 HTML 재생성."
      fi
      exit 0
    fi

    echo "[handover][ERROR] 알 수 없는 mode: $HANDOVER_MODE" >&2
    exit 1
    ;;

  help|--help|-h)
    usage
    ;;

  "")
    usage
    ;;

  *)
    echo "[ERROR] 알 수 없는 명령: $1"
    echo ""
    usage
    exit 1
    ;;
esac
