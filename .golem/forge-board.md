---
project: golem-garden
type: CLI 도구 / AI 에이전트 오케스트레이션 시스템
created: 2026-04-06
updated: 2026-04-18
---

# Forge Board

## 팀 구성

| SOUL | 역할 | OMC Agent | 모델 | Rank | 상태 |
|------|------|-----------|------|------|------|
| Nex | Director | architect | opus | junior | active |
| Ryn | Backend (Bash) | executor | sonnet | junior | active |
| Zen | QA Tester | test-engineer | haiku | novice | active |
| Bolt | DevOps | executor | sonnet | novice | active |

## 기술스택
- Language: Bash (POSIX 호환)
- Data: JSONL (grep/sed 파싱), YAML frontmatter + Markdown
- Platform: oh-my-claudecode (OMC) CLI
- Install: install.sh → ~/.claude/golem-garden/
- Hook: OMC Stop hook (auto-dashboard-refresh)

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
- lib/ 모듈 작업 → Ryn (Bash 전문)
- 테스트/검증 → Zen (QA)
- install.sh, hook, portability → Bolt (DevOps)

## 기술 부채 (Phase 1 분석 기반)
1. ~~JSONL 인젝션 위험~~ — **해결** `_json_escape()` 적용 (2026-04-06)
2. ~~승급 로직 중복~~ — **해결** `rank_should_promote()` 통합 (2026-04-06)
3. ~~무조건 모듈 로딩~~ — **해결** `_load()` lazy loading (2026-04-06)
4. soul_parse() 글로벌 변수 오염 — 미착수 (고비용/중효과, save/restore 패턴으로 우회 중)
5. ~~경로 순회 미검증~~ — **해결** `basename` 검증 추가 (2026-04-06)

## 태스크 히스토리

| 날짜 | 태스크 | 담당 SOUL | 결과 | 비고 |
|------|--------|----------|------|------|
| 2026-04-06 | forge-init | - | success | 프로젝트 초기화 |
| 2026-04-06 | 기술부채 전체수정 | Ryn+Bolt | success | T1~T5 해결 (8파일 +204/-85) |
| 2026-04-06 | 크로스 리뷰 | Zen | pass | HIGH 2건 즉시 수정 |
| 2026-04-07 | 자동 비용 추적 | Ryn | success | log-add-usage + budget_estimate_cost |
| 2026-04-07 | MD 파일 정비 | Ryn | success | README/QUICKSTART/PHILOSOPHY 동기화 |
| 2026-04-18 | 자동승급 시스템 점검 | ryn | success |  |
| 2026-04-18 | 랭크 승급: novice→junior | ryn | success | 전체 프로젝트 태스크 11건 완료 (≥10) |
