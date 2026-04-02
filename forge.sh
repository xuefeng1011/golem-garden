#!/bin/bash
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
fi

# 하위 source에서 덮어쓰지 않도록 export
export GOLEM_DIR GOLEM_PROJECT

source "${GOLEM_ROOT}/lib/soul-parser.sh"
source "${GOLEM_ROOT}/lib/growth-log.sh"
source "${GOLEM_ROOT}/lib/rank-system.sh"
source "${GOLEM_ROOT}/lib/prompt-builder.sh"
source "${GOLEM_ROOT}/lib/forge-review.sh"
source "${GOLEM_ROOT}/lib/portability.sh"
source "${GOLEM_ROOT}/lib/forge-soul.sh"
source "${GOLEM_ROOT}/lib/domain-pack.sh"
source "${GOLEM_ROOT}/lib/knowledge-sync.sh"
source "${GOLEM_ROOT}/lib/mailbox.sh"
source "${GOLEM_ROOT}/lib/session.sh"
source "${GOLEM_ROOT}/lib/error-recovery.sh"
source "${GOLEM_ROOT}/lib/worktree.sh"

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
  status              팀 상태 + SOUL 랭크 확인
  souls               등록된 SOUL 목록
  prompt <name> <task> SOUL 프롬프트 생성 (디버그용)
  rank <name>         SOUL 랭크 확인 + 승급 체크
  promote <name>      SOUL 랭크 승급 실행
  log <name>          SOUL 성장 기록 조회
  log-add <name> <task> <result> [files] [tests]
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

Recovery (에러 복구):
  recover <soul> <task> <reason>
                      3단계 복구 실행
  recover-history <soul>
                      복구 이력 조회

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

Examples:
  forge status
  forge prompt ryn "인증 API 구현"
  forge rank ryn
  forge log-add ryn "REST API 설계" success 5 12
  forge review ryn zen "AuthController"
  forge review ryn                      # 리뷰어 자동 선정
  forge export ryn /path/to/other/project
  forge import /path/to/source ryn
EOF
}

# 메인 라우터
case "${1:-}" in
  init)
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
    if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
      echo "Usage: forge prompt <soul_name> <task>"
      exit 1
    fi
    prompt_build "$2" "$3"
    ;;

  prompt-review)
    if [ -z "${2:-}" ] || [ -z "${3:-}" ] || [ -z "${4:-}" ]; then
      echo "Usage: forge prompt-review <reviewer> <worker> <target>"
      exit 1
    fi
    prompt_build_review "$2" "$3" "$4"
    ;;

  prompt-director)
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
    # 자동 랭크 체크
    rank_check "$2"
    ;;

  dashboard)
    case "${2:-}" in
      --cost|cost)
        growth_log_cost_dashboard
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
    if [ -z "${2:-}" ]; then
      echo "Usage: forge review <worker> [reviewer] [target]"
      exit 1
    fi
    review_execute "$2" "${3:-}" "${4:-전체 변경사항}"
    ;;

  review-record)
    if [ -z "${2:-}" ] || [ -z "${3:-}" ] || [ -z "${4:-}" ] || [ -z "${5:-}" ]; then
      echo "Usage: forge review-record <worker> <reviewer> <target> <result> [issues] [severity]"
      exit 1
    fi
    review_record "$2" "$3" "$4" "$5" "${6:-0}" "${7:-none}"
    ;;

  review-auto)
    if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
      echo "Usage: forge review-auto <worker> <task>"
      exit 1
    fi
    review_auto_trigger "$2" "$3"
    ;;

  review-status)
    review_status
    ;;

  export)
    if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
      echo "Usage: forge export <soul_name> <target_dir>"
      exit 1
    fi
    soul_export "$2" "$3"
    ;;

  import)
    if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
      echo "Usage: forge import <source_dir> <soul_name>"
      exit 1
    fi
    soul_import "$2" "$3"
    ;;

  export-pack)
    if [ -z "${2:-}" ]; then
      echo "Usage: forge export-pack <pack_name> [target_dir]"
      exit 1
    fi
    soul_export_pack "$2" "${3:-.}"
    ;;

  import-pack)
    if [ -z "${2:-}" ]; then
      echo "Usage: forge import-pack <pack_dir>"
      exit 1
    fi
    soul_import_pack "$2"
    ;;

  sync)
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
    if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
      echo "Usage: forge sync-judge <번호> <promote|hold|reject> [사유]"
      exit 1
    fi
    knowledge_judge "$2" "$3" "${4:-}"
    ;;

  sync-promote)
    if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
      echo "Usage: forge sync-promote <soul> <learning>"
      exit 1
    fi
    knowledge_promote "$2" "$3"
    ;;

  portability)
    portability_status
    ;;

  mailbox)
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
      *)
        echo "Usage: forge session <create|status|list|resume|end|log>"
        exit 1
        ;;
    esac
    ;;

  recover)
    if [ -z "${2:-}" ] || [ -z "${3:-}" ] || [ -z "${4:-}" ]; then
      echo "Usage: forge recover <soul> <task> <failure_reason>"
      exit 1
    fi
    error_recover "$2" "$3" "$4"
    ;;

  recover-history)
    if [ -z "${2:-}" ]; then
      echo "Usage: forge recover-history <soul_name>"
      exit 1
    fi
    error_history "$2"
    ;;

  cost-dashboard)
    growth_log_cost_dashboard
    ;;

  worktree)
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

  soul-create)
    if [ -z "${2:-}" ]; then
      echo "Usage: forge soul-create <role> [name] [model]"
      echo "Roles: backend-developer, frontend-developer, devops-engineer, qa-tester, data-analyst, technical-writer, security-auditor"
      exit 1
    fi
    soul_create_from_preset "$2" "${3:-}" "${4:-sonnet}"
    ;;

  soul-custom)
    if [ -z "${2:-}" ] || [ -z "${3:-}" ] || [ -z "${4:-}" ]; then
      echo "Usage: forge soul-custom <name> <role> <specialties> [personality] [model]"
      exit 1
    fi
    soul_create_custom "$2" "$3" "$4" "${5:-}" "${6:-sonnet}"
    ;;

  soul-presets)
    soul_preset_list
    ;;

  soul-create-all)
    soul_create_all_presets
    ;;

  pack)
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
