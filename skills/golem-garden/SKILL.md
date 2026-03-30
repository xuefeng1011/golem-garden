---
name: golem-garden
description: GolemGarden 메인 라우터. "forge"로 시작하는 모든 명령을 처리한다.
trigger: forge
---

# GolemGarden — 실행 스킬

사용자가 "forge"로 시작하는 명령을 입력하면 이 스킬이 트리거된다.
아래 라우팅 규칙에 따라 적절한 서브스킬로 분기하거나 직접 실행한다.

## 명령 라우팅

사용자 입력을 파싱하여 아래 패턴에 매칭:

| 패턴 | 동작 |
|------|------|
| `forge-init: ...` 또는 `forge init: ...` | → `forge-init` 스킬 실행 |
| `forge build: ...` | → `forge-team` 스킬 실행 (ultrapilot 모드) |
| `forge quick: ...` | → `forge-team` 스킬 실행 (autopilot 모드) |
| `forge assign {soul}: ...` | → `forge-team` 스킬 실행 (수동 지정 모드) |
| `forge review ...` | → `forge-review` 스킬 실행 |
| `forge status` | → 아래 직접 실행 |
| `forge souls` | → 아래 직접 실행 |
| `forge rank {name}` | → 아래 직접 실행 |

## 직접 실행 명령어

### forge status
1. Bash로 `bash forge.sh status` 실행 (GOLEM_ROOT에서)
2. 결과를 사용자에게 보여줌

### forge souls
1. Bash로 `bash forge.sh souls` 실행

### forge rank {name}
1. Bash로 `bash forge.sh rank {name}` 실행

### forge dashboard
1. Bash로 `bash forge.sh dashboard` 실행

### forge soul-create {role}
1. Bash로 `bash forge.sh soul-create {role}` 실행
2. 생성된 SOUL 파일 내용을 Read로 확인하여 사용자에게 보여줌

### forge pack install {name}
1. Bash로 `bash forge.sh pack install {name}` 실행

## GOLEM_ROOT 결정

프로젝트 루트에서 `forge.sh`를 찾아 GOLEM_ROOT를 결정한다:
1. 현재 작업 디렉토리에 `forge.sh`가 있으면 → 현재 디렉토리
2. 없으면 → `~/.claude/golem-garden/`에서 찾기
3. 없으면 → 사용자에게 경로 물어보기
