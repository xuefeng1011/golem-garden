---
analyzed: 2026-04-06
analyzer: OMC explore + architect (opus)
---

# GolemGarden 프로젝트 분석 결과

## 개요
- 프로젝트 유형: CLI 도구 / AI 에이전트 오케스트레이션 시스템
- 언어: Bash (POSIX 호환 지향, 순수 Bash — 외부 의존성 없음)
- 플랫폼: oh-my-claudecode (OMC) 위에서 동작

## 구조
- forge.sh (933줄) — CLI 진입점, case-switch 라우터
- lib/ (24개 모듈) — 핵심 라이브러리
- souls/ (12개) — SOUL 페르소나 (YAML frontmatter + Markdown)
- skills/ — OMC 스킬 (golem-garden, forge-init, forge-team, forge-review, forge-sync)
- domain-packs/ — 프리셋 팀 번들 (fullstack, gamedev, trading)
- 데이터: JSONL 기반 성장 기록

## 아키텍처

### 모듈 의존성 핵심 체인
```
soul-parser.sh [FOUNDATION — 18/24 모듈이 의존]
  └── growth-log.sh [12개 모듈이 의존]
        ├── rank-system.sh → dashboard-global/web, forge-review, global-sync
        ├── prompt-builder.sh → error-recovery.sh
        ├── budget.sh, achievement.sh, portability.sh
        └── retrospective.sh, domain-pack.sh, forge-soul.sh
```

### 강점
1. 제로 의존성 — 순수 Bash, 설치 간편
2. 2-tier SOUL 해상도 — .golem/souls/ > souls/ (글로벌)
3. 프롬프트 캐시 최적화 — fork-prefix/suffix 분리 (76% 토큰 절감)
4. 3단계 에러 복구 — 재시도→위임→에스컬레이션
5. 랭크 기반 권한 — 도구 접근, 턴 제한, 격리 모드

### 기술 부채 (5건)
1. **JSONL 인젝션** — growth-log.sh:32-48, mailbox.sh:81 — newline/tab 미이스케이프
2. **승급 로직 중복** — rank-system.sh:41-73 ↔ global-sync.sh:141-154
3. **무조건 모듈 로딩** — forge.sh:39-62 — 24개 전부 source (lazy load 없음)
4. **글로벌 변수 오염** — soul_parse()가 SOUL_NAME 등 덮어씀 → 루프 시 버그
5. **경로 순회 미검증** — _resolve_soul_file()에 basename 체크 없음

### 성능 병목
- 대시보드: O(SOUL × 프로젝트 × 로그줄) — JSONL 전수 grep
- 인덱싱/캐시 없음 — 로그 커지면 선형 저하
- 24개 모듈 무조건 로딩 — `forge help`도 전체 로드

### 보안 고려
- 경로 순회: soul name에 ../../ 가능
- 명령 주입: worktree.sh:42 — git 명령에 미검증 soul name
- JSONL 인젝션: 개행 포함 입력 시 레코드 분리
- 인증 없음: mailbox/session에 접근 제어 없음 (단일 사용자 CLI이므로 허용)

## 권장 개선 (우선순위순)
1. `_json_field()` 헬퍼 — 모든 JSON 문자열 안전 이스케이프 (저비용, 고효과)
2. `basename` 검증 — _resolve_soul_file() + worktree (저비용, 보안)
3. 승급 로직 통합 — 단일 함수로 추출 (중비용, 일관성)
4. lazy loading — forge.sh case별 필요 모듈만 source (중비용, 성능)
5. JSONL 요약 캐시 — .summary 파일로 O(1) 조회 (고비용, 성능)
