# GolemGarden 독립 에이전트 엔진

> 브랜치: `feat/independent-engine` | 코어: `lib/agent-runner.sh`, `lib/session.sh`

---

## 1. 개요 — OMC 디커플

GolemGarden 에이전트 엔진은 OMC(oh-my-claudecode)의 `Agent(subagent_type=...)` 메커니즘과 `soul_to_omc_agent` 매핑에 **의존하지 않는다**.  
대신 `claude` CLI를 직접 소환하여 SOUL 에이전트를 실행한다. 동일한 패턴이 Python Gateway(`session_manager.py`)와 Bash CLI(`lib/agent-runner.sh`) 양쪽에 미러 구현되어 있다.

```
forge run ryn "태스크"
      │
      └─→ lib/agent-runner.sh::agent_run()
                │
                └─→ claude --print --output-format=stream-json ...  (직접 호출)
```

---

## 2. `agent_run` 실행 흐름

```
agent_run <soul_name> <task_text> [session_id] [--dry-run]
```

### (a) SOUL 파싱
```bash
soul_file=$(_resolve_soul_file "$soul_name")
soul_parse "$soul_file"          # SOUL_NAME, SOUL_RANK, SOUL_MODEL, SOUL_TOOLS, ... 전역 설정
```

### (b) 시스템 프롬프트 조립
```bash
_ar_header=$(_build_agent_system_prompt)   # "# SOUL Identity\nYou are **ryn** (junior)..."
_ar_body=$(prompt_build "$soul_name" "$task_text")   # 프로젝트 컨텍스트 + SOUL 컨텍스트 + 태스크
system_prompt="${_ar_header}\n\n${_ar_body}"
```

### (c) claude CLI 소환

```bash
_AGENT_CLAUDE_BASE=(--print --output-format=stream-json --verbose)

# 세션 분기:
#   신규 세션 → --session-id <uuid>
#   기존 세션 (.claude 마커 존재) → --resume <uuid>

claude --print --output-format=stream-json --verbose \
  ( --session-id <uuid> | --resume <uuid> ) \
  --append-system-prompt "$system_prompt" \
  --model "$model_arg" \
  --allowedTools "$tools_csv" \
  -- "$task_text"
```

| 인자 | 출처 |
|------|------|
| `--model` | SOUL frontmatter `model:` → `_map_model()` (opus/sonnet/haiku 별칭 또는 `claude-*` ID 통과) |
| `--allowedTools` | SOUL frontmatter `tools:` → 공백 제거 CSV |
| `--session-id` | 신규 UUID (`_gen_uuid()`: /proc → python → /dev/urandom 폴백) |
| `--resume` | `.golem/sessions/<uuid>.claude` 마커 존재 시 |

### (d) stream-json 파싱
```bash
_AR_RESULT_TEXT=$(_extract_assistant_text "$stream_file")   # type=assistant 블록 text 누적
_parse_stream < "$stream_file"                              # type=result → tokens, duration_ms, is_error
```
출력 변수: `_AR_RESULT_TEXT`, `_AR_IS_ERROR`, `_AR_DURATION_MS`, `_AR_TOKENS_IN`, `_AR_TOKENS_OUT`, `_AR_TOKENS_CACHE`

### (e) growth-log 기록
```bash
growth_log_append "$soul_name" "$task_text" "$result" \
  ... "$_AR_TOKENS_IN" "$_AR_TOKENS_OUT" "$_AR_TOKENS_CACHE" \
  "$cost" "$model_arg" "$_AR_DURATION_MS"
```
비용 계산은 `lib/budget.sh::budget_estimate_cost` 재사용.

### (f) usage 요약 출력 (마지막 줄)
```
<usage> soul=ryn model=sonnet result=success tokens_in=1024 tokens_out=256 tokens_cache=0 duration_ms=3200
```

---

## 3. `forge run` 진입점

`forge.sh:252-262`:

```bash
run)
  # forge run <soul> <task> [session_id]
  source "${GOLEM_ROOT}/lib/agent-runner.sh"
  agent_run "$2" "$3" "${4:-}"
  exit $?
  ;;
```

```bash
# 사용 예
forge run ryn "REST API 설계"
forge run zen "Reply with one word: PONG" sess-abc-123
```

---

## 4. 세션 트리 (parentId / fork / branch / tree)

`lib/session.sh:296-498`

세션 메타(`.golem/sessions/*.meta`)는 `parentId` 필드로 부모-자식 관계를 추적한다.  
루트 세션은 `"parentId":""`.

### 세션 메타 구조
```json
{
  "id": "sess_1717440000_1234",
  "task": "...",
  "status": "active",
  "parentId": "",
  "souls": ["ryn", "kai"],
  "soul_status": {"ryn": "idle", "kai": "working"},
  "last_updated": "2026-06-04T12:00:00"
}
```

### 트리 조작 명령

| 명령 | 함수 | 동작 |
|------|------|------|
| `forge session fork <id>` | `session_fork()` | 지정 세션을 부모로 하는 새 세션 생성. souls 상속, parentId 설정 |
| `forge session branch` | `session_branch()` | 전체 세션 목록 + parentId 열 출력 |
| `forge session tree` | `session_tree()` | parentId 기준 재귀 들여쓰기 렌더링 |

```
# session_tree 출력 예
sess_1000 [completed] 인증 API 구현
  └─ sess_1001 [active] fork: 인증 API 구현
       └─ sess_1002 [active] fork: fork: 인증 API 구현
```

세션 재개 판단: `.golem/sessions/<uuid>.claude` 마커 파일 존재 여부. 성공 소환 후 `agent_run`이 마커를 생성하여 후속 호출이 `--resume`을 타도록 보장한다.

---

## 5. 경량 스킬 증류

`lib/agent-runner.sh:347-375`

성공 태스크가 누적될 때 SOUL의 학습 패턴을 한 줄 lesson으로 압축하여 `soul-memory`에 기록한다.  
새 인프라 없이 기존 `growth_log_task_count` + `memory_record` 재사용.

```
임계값: AGENT_DISTILL_THRESHOLD=5 (기본)
조건:   success_count >= (distilled_count + 1) * 5
```

```bash
_agent_maybe_distill "$soul_name"
# → memory_record "$soul_name" "distillation@${N}-tasks" \
#     "성공 N건 누적 — 검증된 접근을 기본값으로 삼는다." \
#     "distilled,milestone"
```

증류 레코드는 `tags`에 `distilled`를 포함하므로, 기록 파일(`MEMORY_DIR/<soul>.jsonl`)에서  
`grep '"tags":"[^"]*distilled'`로 카운트하여 중복 증류를 방지한다.

---

## 6. 오케스트레이션 경로 선택 (설계 결정)

SOUL을 실행하는 방법은 두 가지다. 어느 경로를 쓸지 아래 기준으로 결정한다.

### (a) `forge run` — 서브프로세스 경로 (기본값)

```bash
GOLEM_PROJECT="$(pwd)" bash ~/.claude/golem-garden/forge.sh run {soul} "{task}"
```

**쓰는 경우:**
- 독립·병렬 SOUL 실행 (각 서브프로세스가 격리된 컨텍스트를 가짐)
- Gateway(Python) 경로와 동일 동작을 보장해야 할 때
- worktree 격리 모드 (각 SOUL이 별도 디렉토리에서 실행)
- growth-log·비용 자동 기록이 필요한 모든 정식 태스크

**트레이드오프:**
- 호스트 컨텍스트를 공유하지 않는다 — 매 호출마다 프로젝트 컨텍스트를 새로 읽는다.
- 중간 도구 사용은 호스트 UI에 스트리밍되지 않는다 — 최종 텍스트 + `<usage>` 줄만 반환된다. 이를 보완하기 위해 실행 전·후 가시성 배너가 필수다.
- `maxTurns`는 claude CLI 플래그 미지원으로 프롬프트 내 권고 텍스트로만 전달된다 (강제 아님). `--allowedTools` / `--model`은 실제 CLI 플래그로 적용된다.

### (b) 호스트 인라인 오케스트레이션 — 컨텍스트 내 경로

호스트(현재 Claude Code 세션)가 직접 파일을 읽고 편집한다.

**쓰는 경우:**
- 단순한 단일 파일 편집처럼 서브프로세스를 띄우는 비용이 컨텍스트 이득보다 클 때
- 호스트의 웜(warm) 컨텍스트가 이미 필요한 정보를 모두 갖고 있을 때
- 분배가 자명해 Nex 위임이 불필요할 때 (`forge-team` Step 2-3-4 참조)

**트레이드오프:**
- growth-log·비용 자동 기록이 없다 — 필요하면 `forge log-add`로 수동 기록해야 한다.
- 호스트 컨텍스트 창을 소모하므로 장시간 세션에서는 `forge run` 경로보다 컨텍스트 압박이 커질 수 있다.
