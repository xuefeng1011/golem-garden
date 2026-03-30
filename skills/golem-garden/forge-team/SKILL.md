---
name: forge-team
description: GolemGarden 팀 단위 작업 실행. SOUL 기반 역할 분배.
trigger: forge build, forge quick, forge save, forge assign
---

# forge-team — 팀 실행

SOUL 기반으로 태스크를 분배하고 OMC 실행 모드로 실행한다.

## 워크플로우

### Step 1: forge-board.md 로드

프로젝트 루트의 `forge-board.md`에서 현재 팀 구성을 읽는다:
- 활성 SOUL 목록
- 각 SOUL의 역할, 모델, 랭크
- OMC 실행 모드 설정

### Step 2: 태스크 분석 및 분배

**분배 모드 판별:**

| 입력 패턴 | 모드 | 동작 |
|----------|------|------|
| `forge build: {task}` | 자동 분배 | Nex가 분석 → SOUL별 배정 |
| `forge assign {soul}: {task}` | 수동 지정 | 지정 SOUL만 실행 |
| `forge build: {task}, {soul} 리드` | 리드 지정 | 리드 SOUL + 나머지 자동 |

**자동 분배 시 Nex(Director)의 판단 기준:**
1. 태스크 키워드와 SOUL `specialty` 매칭
2. SOUL `rank` 기반 권한 범위 확인
3. 가용 SOUL 중 최적 조합 선택

### Step 3: SOUL 컨텍스트 주입

각 배정된 SOUL에 대해:
1. `souls/{name}.md` 로드
2. `growth-log/{name}.jsonl` 에서 최근 이력 요약
3. 프롬프트 조립:
   ```
   [GolemGarden Context — {NAME} ({ROLE})]
   프로젝트 컨텍스트: ...
   전문 지식 힌트: ...
   이전 작업 이력: N건, 성공률 X%
   현재 랭크: {RANK}

   이 컨텍스트에서 다음 태스크를 수행하라:
   {TASK}
   ```

### Step 4: OMC 실행 모드 선택

| 명령 | OMC 모드 | 설명 |
|------|---------|------|
| `forge build` | ultrapilot | SOUL별 병렬, 대규모 태스크 |
| `forge quick` | autopilot | 단일 SOUL, 간단한 태스크 |
| `forge save` | ecomode | haiku 기반, 비용 절약 |
| `forge assign` | autopilot | 지정 SOUL 단독 실행 |

### Step 5: 실행 완료 후 기록

각 SOUL의 태스크 결과를 `growth-log/{name}.jsonl`에 기록:
```json
{"date":"2026-03-30","task":"인증 API 구현","result":"success","files_changed":8,"tests_passed":15}
```

forge-board.md 태스크 히스토리에도 추가.

## 랭크 기반 권한 체크

실행 전 SOUL의 rank에 따른 권한을 확인한다:

| Rank | 허용 범위 |
|------|----------|
| Novice | 단일 파일 수정. 완료 후 자동 리뷰 배정 |
| Junior | 멀티파일 수정, 테스트 작성 가능 |
| Senior | 아키텍처 변경 가능, 자율 실행 |
| Lead | 다른 SOUL에게 서브태스크 위임 가능 |
| Master | 모든 작업 가능, 리뷰 면제 |
