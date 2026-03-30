---
name: golem-garden
description: GolemGarden 메인 스킬. SOUL 기반 AI 에이전트 육성 시스템의 진입점.
trigger: forge
---

# GolemGarden

SOUL 기반 AI 에이전트 육성 시스템. OMC 위에서 동작한다.

## 명령어

| 명령 | 스킬 | 설명 |
|------|------|------|
| `forge-init` | forge-init | 프로젝트 초기화, 팀 구성, SOUL 파일 생성 |
| `forge build` | forge-team | SOUL별 병렬 실행 (ultrapilot) |
| `forge quick` | forge-team | 단일 SOUL 자율 실행 (autopilot) |
| `forge save` | forge-team | 비용 절약 모드 (ecomode) |
| `forge assign` | forge-team | 특정 SOUL에 수동 배정 |
| `forge review` | forge-review | 크로스 리뷰 |
| `forge soul` | forge-soul | 커스텀 SOUL 생성 (대화형) |
| `forge status` | golem-garden | 팀 상태 + SOUL 랭크 확인 |
| `forge pack` | golem-garden | 도메인 스킬 팩 관리 |

## SOUL → OMC 에이전트 매핑

SOUL의 `role` 필드를 기준으로 OMC 에이전트를 매핑한다.

| SOUL Role | OMC Agent | 기본 모델 |
|-----------|-----------|----------|
| director | architect | opus |
| backend-developer | executor | sonnet |
| frontend-developer | designer | sonnet |
| qa-tester | test-engineer | haiku |
| devops-engineer | executor | sonnet |
| data-analyst | scientist | sonnet |
| technical-writer | writer | haiku |
| security-auditor | security-reviewer | opus |

## 랭크 시스템

| 랭크 | 태스크 완료 | 조건 | 권한 |
|------|-----------|------|------|
| Novice | 0 | 생성 직후 | 단일 파일 수정, 리뷰 필수 |
| Junior | 10+ | 태스크 10회 완료 | 멀티파일 수정, 테스트 작성 |
| Senior | 50+ | 무결함 10연속 | 아키텍처 제안, 자율 실행 |
| Lead | 100+ | 멘토링 이력 | 팀 오케스트레이션 |
| Master | 200+ | 커뮤니티 검증 | 모든 권한 |

## 성장 기록 포맷

`growth-log/{name}.jsonl` 에 한 줄씩 추가:
```json
{"date":"2026-03-30","task":"REST API 설계","result":"success","files_changed":5,"tests_passed":12,"reviewer":"zen","review_result":"pass"}
```
