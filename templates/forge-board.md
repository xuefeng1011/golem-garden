---
project: {{PROJECT_NAME}}
type: {{PROJECT_TYPE}}
created: {{DATE}}
updated: {{DATE}}
---

# Forge Board

## 팀 구성

| SOUL | 역할 | OMC Agent | 모델 | Rank | 상태 |
|------|------|-----------|------|------|------|
| Nex | Director | architect | opus | junior | active |
| Ryn | Backend Developer | executor | sonnet | novice | active |

## 기술스택
- Backend: {{BACKEND_STACK}}
- Frontend: {{FRONTEND_STACK}}
- Database: {{DATABASE}}
- Infra: {{INFRA}}

## OMC 실행 모드 설정

| 작업 유형 | 실행 모드 | 설명 |
|----------|----------|------|
| 대규모 빌드 | ultrapilot | SOUL별 병렬 실행 |
| 단순 태스크 | autopilot | 단일 SOUL 자율 실행 |
| 비용 절약 | ecomode | haiku 기반 경량 실행 |
| 리뷰 포함 | pipeline | 작업 → 리뷰 순차 실행 |

## 분배 규칙
- 자동 분배: Nex(Director)가 태스크 분석 → specialty 매칭 → 배정
- 수동 지정: `forge assign {soul}: {task}` 형식으로 직접 배정
- 리드 지정: `forge build: {task}, {soul} 리드` 형식으로 리드 + 자동

## 태스크 히스토리

| 날짜 | 태스크 | 담당 SOUL | 결과 | 비고 |
|------|--------|----------|------|------|
| (자동 누적) | | | | |
