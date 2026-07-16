# FLOW_CONTRACT — Nex 분해 JSON 계약

> 버전: 0.4 | 대상: lib/flow.sh, lib/flow-contract.sh, web/gateway api_flows.py
> 검증 소스 오브 트루스: `api_flows.py` Pydantic `FlowWriteRequest`
> (구 spec/flow.schema.json 은 어느 코드도 참조하지 않는 고아 스펙이라 삭제 —
>  bash `flow_validate_steps` 와의 판정 정합은 `tests/golden/flow-cases/` 교차 계약이 강제)
> v0.3 변경(B-4): 출력 앵커를 "코드펜스 1개"에서 "마지막 줄 컴팩트 JSON"으로
> 단일화. 코드펜스는 `flow_extract_json`의 1차(레거시 호환) 경로로 유지된다.
> v0.4 변경(B-5): steps 선택 필드 `rubric` 추가 — 분해 시점 채점 계약. 실행
> 프롬프트 주입과 verify `[ITEM-k]` 채점이 같은 항목을 사용한다.

---

## 1. Director(Nex)에게 보낼 분배 프롬프트 표준 템플릿

```
당신은 Director(Nex)입니다. 아래 목표를 SOUL 팀에 분배하십시오.

목표: {goal}
사용 가능한 SOUL: {soul_list}

**응답 규칙 (반드시 준수)**
- 분석과 근거는 자유롭게 서술한다.
- 단, 출력의 맨 마지막 줄은 다른 텍스트·코드펜스 없이 아래 형식의 컴팩트 JSON
  한 줄이어야 한다. 파서(`flow_extract_json`)는 마지막 `{` 로 시작하는 줄만 취한다.
- 각 step의 id는 "s1", "s2" 형식의 고유 문자열.
- soul이 빈 문자열("")이면 호스트(오케스트레이터)가 직접 처리.
- deps는 선행 step id 배열 (없으면 []).
- retry: 0~3 정수, 기본 1.
- approval: 승인 게이트 필요 여부 (true/false).
- on_fail: "abort" | "continue" | "goto:<step_id>" 중 하나.
- rubric: (선택, 강력 권장) 완료 판정 기준 문자열 배열 2~4개. 각 항목은 측정
  가능해야 한다 — 파일 경로, 실행 명령, 기대 출력/수치, 마커 중 최소 하나를 포함.
  항목 문자열에 대괄호([ ])와 리터럴 },{ 및 "," 시퀀스 금지 (파서 제약).
- step 객체는 1-depth — task 값에 중첩 객체·리터럴 `},{` 문자열 금지(파서가
  step 경계로 오인해 전체 거부).

{"steps":[{"id":"s1","soul":"ryn","task":"작업 내용","deps":[],"retry":1,"approval":false,"on_fail":"abort","rubric":["tests/bats/test_x.bats 에 신규 케이스 2개 이상","bash tests/bats/run.sh 가 exit 0"]}]}

위 형식 외 다른 응답은 파싱 오류로 처리됩니다.
```

### 1.1 멀티 스텝 예시

```json
{"steps":[
  {"id":"s1","soul":"ryn","task":"lib/flow-contract.sh 파싱 헬퍼 작성","deps":[],"retry":1,"approval":false,"on_fail":"abort"},
  {"id":"s2","soul":"ara","task":"bats 단위 테스트 작성","deps":["s1"],"retry":1,"approval":false,"on_fail":"continue"},
  {"id":"s3","soul":"","task":"PR 설명 초안 작성","deps":["s1","s2"],"retry":0,"approval":true,"on_fail":"abort"}
]}
```

---

## 2. 기존 줄 단위 분배와의 차이 및 마이그레이션

### 2.1 기존 형식 (v0 — 레거시)

```
ryn: lib/flow-contract.sh 파싱 헬퍼 작성
ara: bats 단위 테스트 작성
```

형식: `{soul}: {subtask}` 줄 단위 평문 텍스트

### 2.2 신규 형식 (v1 — JSON)

| 항목 | v0 줄 단위 | v1 JSON |
|------|-----------|---------|
| 파싱 방법 | awk/grep 줄 분리 | flow_extract_json + flow_parse_steps |
| 순서 보장 | 줄 순서 | deps[] DAG |
| 병렬 실행 표현 | 불가 (암묵적) | 동일 deps 셋 = 병렬 가능 (현재 엔진 기본은 직렬 실행) |
| 재시도 | 없음 | retry 필드 |
| 승인 게이트 | 없음 | approval 필드 |
| 실패 전략 | abort 고정 | on_fail 필드 |
| host 직접 처리 | 없음 | soul="" |

### 2.3 마이그레이션 경로

1. **신규 forge build** — v1 JSON 프롬프트 템플릿 사용 (Section 1).
2. **레거시 호출** — Director가 v0 형식으로 응답하면 폴백 규칙(Section 3) 적용.
3. **점진적 전환** — `forge build` 내부에서 JSON 파싱 실패 시 v0 파서로 fallback. 경고 로그 출력.

---

## 3. 폴백 규칙 — JSON 파싱 실패 시

`flow_extract_json` 내부 추출 우선순위(Section 5.1):

```
① ```json 코드펜스 블록(첫 번째, 레거시/멀티라인 호환)
② ①이 없으면 마지막 `{` 로 시작하는 줄 1줄 채택 (v1 앵커 — 신규 기본 경로)
```

①·② 모두 실패(코드펜스도, 마지막 `{` 줄도 없음) 시 — v0 레거시 소비처가 있다면
줄 단위 파서로 재해석:

```
각 줄: "{soul}: {task}" → id=s{N}, soul, task, deps=[], retry=1, approval=false, on_fail=abort
경고: "[WARN] flow: JSON 파싱 실패, v0 줄 단위 폴백 적용" (stderr 출력)

v0 줄 단위도 매칭 실패 → 전체 abort, stderr에 원본 텍스트 출력
```

v0 폴백은 호환성 보장용이며, 신규 Director 프롬프트(Section 1)는 항상 v1 JSON
마지막 줄 계약을 반환해야 한다. v0 폴백 경고 로그 발생 빈도가 1릴리스 동안 0이면
제거 태스크로 승격한다.

---

## 4. flow.schema.json 필드 매핑 표

| JSON 필드 | schema 타입 | 필수 | 설명 |
|-----------|-------------|------|------|
| `id` | `string` | Y | step 고유 식별자 (e.g. "s1") |
| `soul` | `string(soul_name\|empty=host)` | Y | 담당 SOUL 이름; 빈 문자열 = 오케스트레이터 직접 처리 |
| `task` | `string` | Y | step 수행 내용 |
| `deps` | `array(string)` | Y | 선행 step id 목록 (없으면 `[]`) |
| `retry` | `integer(0-3)` | Y | 실패 재시도 횟수, 기본값 1 |
| `approval` | `boolean` | Y | 실행 전 인간 승인 게이트 여부 |
| `on_fail` | `string(abort\|continue\|goto:<step_id>)` | Y | 실패 시 전략 |
| `rubric` | `array(string)` 2~4항목 | N (기본 `[]`) | 스텝 완료 판정 기준. 부재 시 verify가 채점 시점 자체 생성(레거시). 항목 제약은 §5.1 참조 |
| `status` | `string(pending\|…)` | 런타임 | lib/flow.sh가 실행 중 기록, Director 응답에는 불포함 |

> `status`는 Director 응답 JSON에 없어도 된다. lib/flow.sh가 런타임에 `pending`으로 초기화한다.

---

## 5. 파서 모듈 계약

| 함수 | 위치 | 입력 | 출력 |
|------|------|------|------|
| `flow_extract_json` | lib/flow-contract.sh | stdin 또는 파일 | JSON 텍스트 (stdout) — 코드펜스 우선, 없으면 마지막 `{` 줄 폴백 |
| `flow_steps_array` | lib/flow-contract.sh | stdin (`{"steps":[...]}` 또는 배열) | `[...]` 배열 (stdout) — `mission set-tasks-json` 직결용 언랩 |
| `flow_parse_steps` | lib/flow-contract.sh | stdin (JSON) | US(0x1f) 구분 레코드 `id␟soul␟task␟deps` (stdout, `IFS=$'\037' read`로 소비 — 탭은 빈 필드가 접혀 사용 불가) |
| `flow_validate_steps` | lib/flow-contract.sh | stdin (JSON) | 0=valid / 비-0=위반 + stderr 사유 |
| `_fc_get_rubric` | lib/flow-contract.sh | step 객체 1줄 | 항목 1개=1줄 (unescape 된 평문, stdout). 부재 시 빈 출력 |

이 함수들이 lib/flow.sh의 유일한 진입점이다. jq 직접 호출 금지.
mission 레인 직결 배선: `flow_extract_json | flow_steps_array | forge mission set-tasks-json {id} -`.

### 5.1 파서 한계

`flow_parse_steps`/`flow_validate_steps`는 jq 없이 sed/grep 기반 1-depth
텍스트 파서다. task 값 리터럴에 `},{`가 섞이면 step 경계 오분할로 오인될 수
있어 `flow_validate_steps`가 이를 파편으로 감지해 거부한다(HIGH-3, 오탐
방지는 `tests/golden/flow-cases/`로 교차 검증). 근본 해결(문자 단위 JSON
파서 도입)은 이번 범위 밖이며, 별도 태스크로 남겨둔다.

retry 기본값은 bash(`lib/flow.sh`) 1 / Pydantic(`api_flows.py`) 1 / 본
문서(Section 1, 4) 1로 모두 정렬되어 있다.

`rubric` 배열 추출은 `[^]]*` 기반이라 항목 내 `]`에서 조기 종료하고, 항목
분할은 `","` 시퀀스 경계다. `flow_validate_steps`는 rubric 제약 위반 시
**step을 거부하지 않고 rubric 필드만 폐기 + `[WARN]`** — rubric은 선택적
강화 필드이므로 위반이 분해 전체를 죽여선 안 된다(관대 소비 원칙).

### 5.2 이스케이프 처리 (`_flow_unescape`, lib/flow.sh)

`{{step_id}}` 출력 치환 시 `\n`/`\t`/`\\`/`\"`는 복원하지만, `\b`(backspace)와
`\f`(formfeed)는 저장측(`_flow_json_escape`)에 대칭 이스케이프가 없어 의도적으로
복원하지 않는 gap 이다 (근거는 `lib/flow.sh` 해당 함수 상단 주석 참조).
