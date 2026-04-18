---
analyzed: 2026-04-18
analyzer: OMC explore + architect (opus)
previous: 2026-04-06
---

# GolemGarden 프로젝트 분석 결과 (v2)

## 개요
- 프로젝트 유형: AI 에이전트 페르소나(SOUL) 관리 + 육성 시스템
- 언어: Bash (POSIX 호환) + HTML/JS (대시보드)
- 플랫폼: Claude Code CLI + OMC 위에서 동작
- 포터빌리티: agentskills.io 호환 (SOUL Spec v1.0)

## 규모 (2026-04-06 대비 변화)

| 항목 | 이전 | 현재 | 변화 |
|------|------|------|------|
| lib/ 모듈 | 24개 | 28개 | +4 (lesson-extractor, insights, dashboard-unified, soul-to-skill, skill-to-soul) |
| lib/ 코드 | ~5,500줄 | 7,707줄 | +40% |
| skills/ | 5개 | 6개 | +1 (forge-soul) |
| spec/ | 0 | 3파일 | 신규 (SOUL Spec v1.0) |
| SOUL 수 | 12 | 12 | 동일 |
| forge.sh | 933줄 | ~1,060줄 | +13% |

## 아키텍처

### 모듈 의존성 (갱신)
```
soul-parser.sh [FOUNDATION — 20/28 모듈 의존]
  └── growth-log.sh [14개 모듈 의존]
        ├── rank-system.sh → auto-promote + tools/maxTurns/isolation 갱신
        ├── prompt-builder.sh → error-recovery.sh (13종 에러 분류)
        ├── insights.sh (신규) → 성과 패턴 분석
        ├── lesson-extractor.sh (신규) → 학습 자동 추출
        ├── dashboard-unified.sh (신규) → CLI 통합 대시보드
        ├── soul-to-skill.sh (신규) → agentskills.io 변환
        ├── skill-to-soul.sh (신규) → Agent Skill 역변환
        └── budget.sh, achievement.sh, chemistry.sh ...
```

### 자동화 체인 (이전 대비 완성도)
```
이전 (v1, 2026-04-06):
  log-add → growth_log → rank_check(보고만) → 끝
  ❌ 자동 승급 없음, ❌ 업적 없음, ❌ 학습 없음

현재 (v2, 2026-04-18):
  log-add → growth_log → rank_promote(자동!) → tools/maxTurns/isolation 갱신
                        → achievement_check(자동!)
  forge-team → 학습 추출(lesson-extractor) → memory_record
  ✅ 완전 자동화
```

### 에러 복구 (이전 대비)
```
이전: 5종 분류 (timeout, rate_limit, file_not_found, lock_conflict, permission)
현재: 13종 분류 + 복구 힌트 (context_overflow, model_not_found, auth, billing 등)
```

## 현재 팀 구성 평가

### 활동 SOUL (3/12)
| SOUL | Role | Rank | 태스크 | 성공률 | 역할 적합도 |
|------|------|------|--------|--------|------------|
| **Ryn** | backend-developer | **junior** | 8건 | 80% | 적합 — Bash/POSIX 전문화 |
| **Zen** | qa-tester | novice | 3건 | 100% | 적합 — 리뷰 전담 |
| **Bolt** | devops-engineer | novice | 1건 | 50% | 적합 — 설치/훅 관리 |

### 비활동 SOUL (9/12) — 적합도 평가
| SOUL | Role | 이 프로젝트에 필요? | 판정 |
|------|------|---------------------|------|
| **Nex** | director | 필요 — 팀 빌드 시 분배자 | **유지** |
| **Sage** | knowledge-auditor | 필요 — 지식 승격 심사 | **유지** |
| **Kai** | frontend-developer | 필요 — 대시보드 HTML 작업 | **유지** |
| Glitch | game-logic-developer | 불필요 — 게임 프로젝트용 | 대기 |
| Oracle | data-analyst | 불필요 — 트레이딩용 | 대기 |
| Pixel | frontend-developer | 불필요 — Kai와 중복 | 대기 |
| Scout | data-analyst | 불필요 — 뉴스 분석용 | 대기 |
| Sentinel | security-auditor | 불필요 — 트레이딩용 | 대기 |
| Sprite | game-designer | 불필요 — 게임 프로젝트용 | 대기 |

### 팀 구성 권고
이 프로젝트(GolemGarden 자체 개발)에 **실제 필요한 SOUL은 6명**:
- Nex (Director), Ryn (Backend/Bash), Zen (QA), Bolt (DevOps), Kai (Frontend/HTML), Sage (Auditor)
- 나머지 6명은 다른 프로젝트(gamedev, trading)용 → 대기 상태 정상

## 이전 분석 기술 부채 해소 현황

| # | 부채 | 이전 상태 | 현재 |
|---|------|----------|------|
| 1 | JSONL 인젝션 | 미해결 | **부분 해결** — `_json_escape` 사용 중이나 전체 적용 미완 |
| 2 | 승급 로직 중복 | 미해결 | **해결** — `rank_promote`로 통합, 자동 호출 |
| 3 | 무조건 모듈 로딩 | 미해결 | **해결** — `_load()` lazy loader 도입 완료 |
| 4 | 글로벌 변수 오염 | 미해결 | **미해결** — soul_parse()가 여전히 전역 변수 사용 |
| 5 | 경로 순회 미검증 | 미해결 | **미해결** — basename 체크 아직 없음 |

## 신규 기능 (2026-04-06 이후 추가)

| 기능 | 파일 | 설명 |
|------|------|------|
| SOUL Spec v1.0 | spec/ | 플랫폼 독립 표준 + JSON Schema |
| agentskills.io 변환 | soul-to-skill.sh, skill-to-soul.sh | 양방향 포터빌리티 |
| 학습 자동 추출 | lesson-extractor.sh | 구조화된 학습 판단 + memory_record |
| 에러 분류 13종 | error-recovery.sh | 복구 힌트 시스템 |
| SOUL 인사이트 | insights.sh | 성과 패턴 분석 |
| 통합 대시보드 | dashboard-unified.sh | CLI 한눈에 보기 |
| 웹 대시보드 개선 | dashboard/index.html | 테이블+사이드패널+알림+XSS방지 |
| 자동 승급 체인 | rank-system.sh, forge.sh | log-add → promote → tools 갱신 → achievement |
| forge 절대 규칙 | CLAUDE.md | 스킬 강제 호출 + SOUL 가시성 |

## 남은 과제 (우선순위순)

1. **글로벌 변수 오염** — soul_parse()를 local 반환 방식으로 리팩터 (중비용, 높은 안정성 효과)
2. **경로 순회 검증** — _resolve_soul_file()에 basename 가드 (저비용, 보안)
3. **JSONL 인젝션 완전 해결** — 모든 입력 경로에 _json_escape 적용 (중비용)
4. **Python 코어 추출 시작** — SOUL Spec 기반 플랫폼 독립 모듈 (고비용, 전략적)
5. **Hermes Agent 플러그인** — Python 코어 완성 후 (고비용, Phase 3)
