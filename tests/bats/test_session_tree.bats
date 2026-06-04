#!/usr/bin/env bats
# test_session_tree.bats — Zen 작성: session.sh 세션 트리 + 회귀 테스트
# T2 커버리지:
#   session_create, session_fork (parentId), session_tree, session_branch,
#   기존 session_create/status/list/resume/end 회귀

load "test_helper"

# session.sh 소싱 후 SESSION_DIR을 TEST_PROJECT 기반으로 고정.
# soul-parser.sh 가 source 시 GOLEM_DIR 을 GOLEM_ROOT 로 덮어쓰므로
# source 전에 export 하고, source 후에도 재설정 + mkdir 강제.
_source_session() {
  export GOLEM_DIR="$TEST_PROJECT/.golem"
  export GROWTH_DIR="$TEST_PROJECT/.golem/growth-log"
  # souls/mailbox 만 미리 생성. sessions 는 _session_ensure_dir 에 맡긴다.
  # (_session_ensure_dir 은 "[ ! -d ] && mkdir" 패턴이므로 디렉터리가
  # 이미 존재하면 set -e 환경에서 exit 1 이 된다 — 사전 생성 금지)
  mkdir -p "$GOLEM_DIR/souls" "$GOLEM_DIR/mailbox"
  # shellcheck source=/dev/null
  source "${GOLEM_ROOT}/lib/session.sh"
  # soul-parser.sh 가 GOLEM_DIR 을 GOLEM_ROOT 로 덮어쓰므로 재설정
  export GOLEM_DIR="$TEST_PROJECT/.golem"
  export GROWTH_DIR="$TEST_PROJECT/.golem/growth-log"
  # SESSION_DIR 재계산 (GOLEM_DIR 덮어쓰기 이후)
  SESSION_DIR="${GOLEM_DIR}/sessions"
  # sessions 디렉터리는 여기서 생성하지 않는다 — _session_ensure_dir 가 담당
}

# ─────────────────────────────────────────────────────────
# 회귀: session_create
# ─────────────────────────────────────────────────────────

@test "session: session_create — 메타 파일 생성" {
  _source_session
  session_create "REST API 구현" "zen,ryn"

  # SESSION_DIR 안에 .meta 파일이 하나 이상 존재해야 함
  local count
  count=$(ls "$SESSION_DIR"/*.meta 2>/dev/null | wc -l)
  [ "$count" -ge 1 ]
}

@test "session: session_create — 메타 파일에 id 필드 존재" {
  _source_session
  session_create "인증 모듈 작성" "zen"

  local meta_file
  meta_file=$(ls -t "$SESSION_DIR"/*.meta | head -1)
  grep -q '"id"' "$meta_file"
}

@test "session: session_create — 메타 파일에 status:active" {
  _source_session
  session_create "인증 모듈 작성" "zen"

  local meta_file
  meta_file=$(ls -t "$SESSION_DIR"/*.meta | head -1)
  grep -q '"status":"active"' "$meta_file"
}

@test "session: session_create — 루트 세션 parentId 빈 문자열" {
  _source_session
  session_create "루트 세션 태스크" "zen"

  local meta_file
  meta_file=$(ls -t "$SESSION_DIR"/*.meta | head -1)
  grep -q '"parentId":""' "$meta_file"
}

@test "session: session_create — active 파일 생성" {
  _source_session
  session_create "테스트 세션" "ryn"

  [ -f "$SESSION_DIR/active" ]
}

@test "session: session_create — 트랜스크립트 .jsonl 파일 생성" {
  _source_session
  session_create "트랜스크립트 테스트" "zen"

  local count
  count=$(ls "$SESSION_DIR"/*.jsonl 2>/dev/null | wc -l)
  [ "$count" -ge 1 ]
}

# ─────────────────────────────────────────────────────────
# 회귀: session_status
# ─────────────────────────────────────────────────────────

@test "session: session_status — 활성 세션 있으면 출력 성공" {
  _source_session
  session_create "상태 테스트" "zen"

  run session_status
  [ "$status" -eq 0 ]
  [[ "$output" =~ "세션 상태" ]]
}

@test "session: session_status — 활성 세션 없으면 에러" {
  _source_session

  run session_status
  [ "$status" -ne 0 ]
}

# ─────────────────────────────────────────────────────────
# 회귀: session_list
# ─────────────────────────────────────────────────────────

@test "session: session_list — 세션 생성 후 목록에 포함" {
  _source_session
  session_create "목록 테스트" "zen"

  run session_list
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Sessions" ]]
}

# ─────────────────────────────────────────────────────────
# 회귀: session_end
# ─────────────────────────────────────────────────────────

@test "session: session_end — completed 상태로 종료" {
  _source_session
  session_create "종료 테스트" "zen"

  session_end "completed"

  # active 파일 제거 확인
  [ ! -f "$SESSION_DIR/active" ]
}

@test "session: session_end — 메타 파일 status 갱신" {
  _source_session
  session_create "상태 갱신 테스트" "zen"

  local meta_file
  meta_file=$(ls -t "$SESSION_DIR"/*.meta | head -1)

  session_end "completed"
  grep -q '"status":"completed"' "$meta_file"
}

# ─────────────────────────────────────────────────────────
# 회귀: session_resume
# ─────────────────────────────────────────────────────────

@test "session: session_resume — 활성 세션 재개 성공" {
  _source_session
  session_create "재개 테스트" "zen"

  run session_resume
  [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────────────────
# T2 핵심: session_fork — parentId 메타데이터
# ─────────────────────────────────────────────────────────

# NOTE: _session_ensure_dir 는 "[ ! -d ] && mkdir" 패턴을 사용한다.
# bats set -e 환경에서 디렉터리가 이미 존재하면 [ ! -d ] 가 false(exit 1) 를 반환하여
# && 단락 평가로 인해 전체 명령이 exit 1 이 된다.
# session_fork 는 session_create 이후 호출되므로 sessions 디렉터리가 이미 존재한다.
# 따라서 session_fork 를 직접 호출하면 set -e 로 인해 테스트가 abort 된다.
# 모든 session_fork 호출은 `run` 으로 감싸서 bats 가 exit code 를 포착하게 한다.
# 이 버그는 lib/session.sh 의 _session_ensure_dir 에 있으며, 수정은 다른 SOUL 의 몫이다.
# (findings 섹션 참조)

# ─── 공통 헬퍼: session_create 후 parent_id 추출 + run session_fork ───
# 반환: child meta 파일 경로를 $CHILD_META_FILE 전역에 설정
_fork_from_latest() {
  local parent_id
  parent_id=$(grep -o '"id":"[^"]*"' "$(ls -t "$SESSION_DIR"/*.meta | head -1)" | head -1 | sed 's/"id":"//;s/"//')
  run session_fork "$parent_id"
  [ "$status" -eq 0 ]
  CHILD_META_FILE="${SESSION_DIR}/$(cat "$SESSION_DIR/active").meta"
  FORKED_PARENT_ID="$parent_id"
}

@test "session: session_fork — 부모 세션에서 포크 성공" {
  _source_session
  session_create "부모 태스크" "zen,ryn"
  _fork_from_latest

  [ -f "$CHILD_META_FILE" ]
}

@test "session: session_fork — 자식 메타에 parentId = 부모 id" {
  _source_session
  session_create "부모 태스크" "zen"
  _fork_from_latest

  # 자식의 parentId가 부모 id와 일치해야 함 (핵심 불변성)
  grep -q "\"parentId\":\"${FORKED_PARENT_ID}\"" "$CHILD_META_FILE"
}

@test "session: session_fork — 자식 메타에 status:active" {
  _source_session
  session_create "부모 태스크" "zen"
  _fork_from_latest

  grep -q '"status":"active"' "$CHILD_META_FILE"
}

@test "session: session_fork — 자식 id는 부모 id와 다름" {
  _source_session
  session_create "부모 태스크" "zen"
  _fork_from_latest

  local child_id
  child_id=$(grep -o '"id":"[^"]*"' "$CHILD_META_FILE" | head -1 | sed 's/"id":"//;s/"//')

  [ "$child_id" != "$FORKED_PARENT_ID" ]
}

@test "session: session_fork — 존재하지 않는 부모 id → 에러" {
  _source_session

  run session_fork "nonexistent-sess-xyz"
  [ "$status" -ne 0 ]
}

# ─────────────────────────────────────────────────────────
# T2 핵심: session_tree — 두 세션 모두 포함
# ─────────────────────────────────────────────────────────

@test "session: session_tree — 루트 + 자식 ID 모두 출력에 포함" {
  _source_session
  session_create "루트 태스크" "zen"
  _fork_from_latest

  local child_id
  child_id=$(grep -o '"id":"[^"]*"' "$CHILD_META_FILE" | head -1 | sed 's/"id":"//;s/"//')

  run session_tree
  [ "$status" -eq 0 ]
  [[ "$output" =~ "$FORKED_PARENT_ID" ]]
  [[ "$output" =~ "$child_id" ]]
}

@test "session: session_tree — 자식이 들여쓰기(└─)로 렌더링" {
  _source_session
  session_create "루트 태스크" "zen"
  _fork_from_latest

  run session_tree
  [ "$status" -eq 0 ]
  [[ "$output" =~ "└─" ]]
}

# ─────────────────────────────────────────────────────────
# T2 핵심: session_branch — 부모 링크 표시
# ─────────────────────────────────────────────────────────

@test "session: session_branch — 루트는 (root) 표시" {
  _source_session
  session_create "브랜치 테스트 루트" "zen"

  # 부모가 없으므로 (root) 표시
  run session_branch
  [ "$status" -eq 0 ]
  [[ "$output" =~ "(root)" ]]
}

@test "session: session_branch — 자식은 parentId 표시" {
  _source_session
  session_create "브랜치 테스트 루트" "zen"
  _fork_from_latest

  run session_branch
  [ "$status" -eq 0 ]
  [[ "$output" =~ "$FORKED_PARENT_ID" ]]
}

@test "session: session_branch — 두 세션 모두 목록에 표시" {
  _source_session
  session_create "브랜치 테스트" "zen"
  _fork_from_latest

  local child_id
  child_id=$(grep -o '"id":"[^"]*"' "$CHILD_META_FILE" | head -1 | sed 's/"id":"//;s/"//')

  run session_branch
  [ "$status" -eq 0 ]
  [[ "$output" =~ "$FORKED_PARENT_ID" ]]
  [[ "$output" =~ "$child_id" ]]
}

# ─────────────────────────────────────────────────────────
# 엣지 케이스
# ─────────────────────────────────────────────────────────

@test "session: session_fork — souls 배열 부모에서 상속" {
  _source_session
  session_create "SOUL 상속 테스트" "zen,ryn"
  _fork_from_latest

  # 부모의 souls(zen, ryn)가 자식에 상속되어야 함
  grep -q '"souls"' "$CHILD_META_FILE"
  grep -q 'zen' "$CHILD_META_FILE"
}

@test "session: session_fork — 트랜스크립트에 session_fork 이벤트 기록" {
  _source_session
  session_create "포크 이벤트 테스트" "zen"
  _fork_from_latest

  local child_transcript
  child_transcript="${SESSION_DIR}/$(cat "$SESSION_DIR/active").jsonl"

  [ -f "$child_transcript" ]
  grep -q '"action":"session_fork"' "$child_transcript"
}
