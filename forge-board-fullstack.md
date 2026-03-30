---
project: (풀스택 프로젝트명)
type: fullstack
created: 2026-03-30
updated: 2026-03-30
---

# Forge Board — 풀스택 웹앱

## 팀 구성

| SOUL | 역할 | OMC Agent | 모델 | Rank | 상태 |
|------|------|-----------|------|------|------|
| Nex | Director | architect | opus | junior | active |
| Ryn | Backend | executor | sonnet | novice | active |
| Kai | Frontend | designer | sonnet | novice | active |
| Zen | QA | test-engineer | haiku | novice | active |
| Bolt | DevOps | executor | sonnet | novice | active |

## 기술스택
- Backend: Spring Boot 3.x + WebFlux, MariaDB
- Frontend: React 18 + Next.js, TypeScript, Tailwind
- Infra: Docker, GitHub Actions

## OMC 실행 모드 설정

| 작업 유형 | 실행 모드 | 설명 |
|----------|----------|------|
| 풀스택 빌드 | ultrapilot | Backend+Frontend+DevOps 병렬 |
| API 개발 | autopilot | Ryn 단독 |
| UI 개발 | autopilot | Kai 단독 |
| 리뷰 포함 | pipeline | 개발 → Zen 리뷰 순차 |
| 배포 | pipeline | Bolt CI/CD → 모니터링 |
