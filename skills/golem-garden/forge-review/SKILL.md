---
name: forge-review
description: GolemGarden 팀 크로스 리뷰. 다른 SOUL이 코드 리뷰.
trigger: forge review
---

# forge-review — 크로스 리뷰

작업자와 다른 역할의 SOUL이 코드를 리뷰한다.

## 워크플로우

### Step 1: 리뷰 대상 파악

- `forge review: {soul}이 작성한 {target}을 {reviewer}가 리뷰`
- reviewer 미지정 시 자동 선정:
  - Backend 코드 → QA SOUL 또는 다른 Backend SOUL
  - Frontend 코드 → QA SOUL 또는 Director SOUL
  - 인프라 코드 → Security SOUL 또는 Director SOUL

### Step 2: 리뷰어 SOUL 컨텍스트 로드

1. 리뷰어의 `souls/{name}.md` 로드
2. 리뷰어의 전문 지식 + 행동 원칙을 리뷰 프롬프트에 주입
3. 리뷰 관점 설정:
   ```
   [GolemGarden Review — {REVIEWER_NAME} ({ROLE})]
   리뷰 관점:
   - 전문 분야: {SPECIALTY}
   - 중점 체크: {REVIEW_FOCUS}

   작업자: {WORKER_NAME} ({WORKER_ROLE}), Rank: {WORKER_RANK}
   리뷰 대상: {TARGET_FILES}
   ```

### Step 3: 리뷰 실행

OMC의 `code-reviewer` 에이전트를 리뷰어 SOUL 컨텍스트와 함께 실행:
- 코드 품질 체크
- SOUL의 전문 지식 기반 도메인 특화 리뷰
- 프로젝트 컨벤션 준수 확인

### Step 4: 결과 기록

**작업자 growth-log:**
```json
{"date":"2026-03-30","task":"AuthController 리뷰","result":"pass","reviewer":"zen","issues_found":0}
```

**리뷰어 growth-log:**
```json
{"date":"2026-03-30","task":"AuthController 리뷰 (reviewer)","result":"success","issues_found":2,"severity":"minor"}
```

### Step 5: 랭크 승급 체크

리뷰 결과에 따라 작업자의 랭크 승급을 확인:
1. `growth-log/{name}.jsonl` 에서 전체 이력 로드
2. 태스크 완료 횟수 카운트
3. 연속 무결함(issues_found=0) 카운트
4. 승급 조건 충족 시:
   - `souls/{name}.md`의 `rank` 필드 업데이트
   - growth-log에 승급 이벤트 기록:
     ```json
     {"date":"2026-03-30","task":"RANK_UP","result":"junior→senior","trigger":"무결함 10연속 달성"}
     ```

## 리뷰 자동 트리거

Novice/Junior SOUL의 작업 완료 시 자동으로 리뷰가 트리거된다:
- forge-team 실행 → 완료 → rank 확인 → Novice/Junior면 forge-review 자동 실행
- Senior 이상은 리뷰 선택적 (사용자 요청 시에만)
