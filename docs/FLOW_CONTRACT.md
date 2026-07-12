# FLOW_CONTRACT — Nex 분해 JSON 계약

> 버전: 0.2 | 대상: lib/flow.sh, lib/flow-contract.sh, web/gateway api_flows.py
> 검증 소스 오브 트루스: `api_flows.py` Pydantic `FlowWriteRequest`
> (구 spec/flow.schema.json 은 어느 코드도 참조하지 않는 고아 스펙이라 삭제 —
>  bash `flow_validate_steps` 와의 판정 정합은 `tests/golden/flow-cases/` 교차 계약이 강제)

---

## 1. Director(Nex)에게 보낼 분배 프롬프트 표준 템플릿

```
당신은 Director(Nex)입니다. 아래 목표를 SOUL 팀에 분배하십시오.

목표: {goal}
사용 가능한 SOUL: {soul_list}

**응답 규칙 (반드시 준수)**
- 응답은 아래 형식의 JSON 코드펜스 1개만 반환한다.
- 설명문, 추가 텍스트, 코드펜스 복수 사용 금지.
- 각 step의 id는 "s1", "s2" 형식의 고유 문자열.
- soul이 빈 문자열("")이면 호스트(오케스트레이터)가 직접 처리.
- deps는 선행 step id 배열 (없으면 []).
- retry: 0~3 정수, 기본 1.
- approval: 승인 게이트 필요 여부 (true/false).
- on_fail: "abort" | "continue" | "goto:<step_id>" 중 하나.

```json
{"steps":[{"id":"s1","soul":"ryn","task":"작업 내용","deps":[],"retry":1,"approval":false,"on_fail":"abort"}]}
```

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

```
flow_extract_json 실패 (코드펜스 없음) → v0 줄 단위 파서로 재해석
  각 줄: "{soul}: {task}" → id=s{N}, soul, task, deps=[], retry=1, approval=false, on_fail=abort
  경고: "[WARN] flow: JSON 파싱 실패, v0 줄 단위 폴백 적용" (stderr 출력)

v0 줄 단위도 매칭 실패 → 전체 abort, stderr에 원본 텍스트 출력
```

폴백은 호환성 보장용이며, 신규 Director 프롬프트는 항상 v1 JSON을 반환해야 한다.

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
| `status` | `string(pending\|…)` | 런타임 | lib/flow.sh가 실행 중 기록, Director 응답에는 불포함 |

> `status`는 Director 응답 JSON에 없어도 된다. lib/flow.sh가 런타임에 `pending`으로 초기화한다.

---

## 5. 파서 모듈 계약

| 함수 | 위치 | 입력 | 출력 |
|------|------|------|------|
| `flow_extract_json` | lib/flow-contract.sh | stdin 또는 파일 | JSON 코드펜스 내용 (stdout) |
| `flow_parse_steps` | lib/flow-contract.sh | stdin (JSON) | US(0x1f) 구분 레코드 `id␟soul␟task␟deps` (stdout, `IFS=$'\037' read`로 소비 — 탭은 빈 필드가 접혀 사용 불가) |
| `flow_validate_steps` | lib/flow-contract.sh | stdin (JSON) | 0=valid / 비-0=위반 + stderr 사유 |

이 세 함수가 lib/flow.sh의 유일한 진입점이다. jq 직접 호출 금지.

### 5.1 파서 한계

`flow_parse_steps`/`flow_validate_steps`는 jq 없이 sed/grep 기반 1-depth
텍스트 파서다. task 값 리터럴에 `},{`가 섞이면 step 경계 오분할로 오인될 수
있어 `flow_validate_steps`가 이를 파편으로 감지해 거부한다(HIGH-3, 오탐
방지는 `tests/golden/flow-cases/`로 교차 검증). 근본 해결(문자 단위 JSON
파서 도입)은 이번 범위 밖이며, 별도 태스크로 남겨둔다.

retry 기본값은 bash(`lib/flow.sh`) 1 / Pydantic(`api_flows.py`) 1 / 본
문서(Section 1, 4) 1로 모두 정렬되어 있다.

### 5.2 이스케이프 처리 (`_flow_unescape`, lib/flow.sh)

`{{step_id}}` 출력 치환 시 `\n`/`\t`/`\\`/`\"`는 복원하지만, `\b`(backspace)와
`\f`(formfeed)는 저장측(`_flow_json_escape`)에 대칭 이스케이프가 없어 의도적으로
복원하지 않는 gap 이다 (근거는 `lib/flow.sh` 해당 함수 상단 주석 참조).
