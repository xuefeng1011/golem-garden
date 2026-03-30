#!/bin/bash
# forge.sh — GolemGarden CLI 진입점
# Usage: bash forge.sh <command> [args...]

set -e

GOLEM_ROOT="$(cd "$(dirname "$0")" && pwd)"
source "${GOLEM_ROOT}/lib/soul-parser.sh"
source "${GOLEM_ROOT}/lib/growth-log.sh"
source "${GOLEM_ROOT}/lib/rank-system.sh"
source "${GOLEM_ROOT}/lib/prompt-builder.sh"
source "${GOLEM_ROOT}/lib/forge-review.sh"
source "${GOLEM_ROOT}/lib/portability.sh"
source "${GOLEM_ROOT}/lib/forge-soul.sh"
source "${GOLEM_ROOT}/lib/domain-pack.sh"

# 도움말
usage() {
  cat <<EOF
GolemGarden — AI 에이전트 육성 시스템

Usage: forge <command> [args...]

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
    cat "${GOLEM_ROOT}/growth-log/${2}.jsonl" 2>/dev/null || echo "(기록 없음)"
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
    growth_log_dashboard
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

  portability)
    portability_status
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
