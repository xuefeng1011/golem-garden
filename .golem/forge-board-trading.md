---
project: (트레이딩 프로젝트명)
type: trading
created: 2026-03-30
updated: 2026-03-30
---

# Forge Board — 주식/크립토 분석

## 팀 구성

| SOUL | 역할 | OMC Agent | 모델 | Rank | 상태 |
|------|------|-----------|------|------|------|
| Nex | Director | architect | opus | junior | active |
| Oracle | 기술적 분석 | scientist | sonnet | novice | active |
| Sentinel | 리스크 관리 | security-reviewer | opus | novice | active |
| Scout | 뉴스/센티먼트 | scientist | haiku | novice | active |

## 기술스택
- Language: Python 3.11+
- Data: pandas, numpy, ta-lib
- Visualization: matplotlib, plotly
- Alert: Discord webhook, Telegram bot

## OMC 실행 모드 설정

| 작업 유형 | 실행 모드 | 설명 |
|----------|----------|------|
| 종합 분석 | ultrapilot | TA+뉴스+리스크 병렬 |
| 단일 종목 분석 | autopilot | Oracle 단독 |
| 백테스트 | pipeline | Oracle 전략 → Sentinel 리스크 순차 |
| 알림 설정 | autopilot | Scout 단독 |
