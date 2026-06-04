#!/usr/bin/env bats
# test_mission.bats — Zen 작성: lib/mission.sh 전체 라이프사이클 + 엣지케이스
# 커버리지:
#   mission_init, mission_set_tasks, mission_task,
#   mission_status, mission_list, mission_complete,
#   엣지케이스(빈 goal, 특수문자, 범위 초과 idx, 동초 충돌 방지)

load "test_helper"

# mission.sh 소싱 후 GOLEM_DIR / MISSION_DIR 을 TEST_PROJECT 기반으로 고정.
# soul-parser.sh 가 GOLEM_DIR 을 GOLEM_ROOT 로 덮어쓰므로
# source 전에 export 하고, source 후에도 재설정한다.
_source_mission() {
  export GOLEM_DIR="$TEST_PROJECT/.golem"
  export GOLEM_PROJECT="$TEST_PROJECT"
  mkdir -p "$GOLEM_DIR/souls" "$GOLEM_DIR/mailbox"
  # shellcheck source=/dev/null
  source "${GOLEM_ROOT}/lib/mission.sh"
  # soul-parser.sh 가 GOLEM_DIR 을 덮어쓰므로 재설정
  export GOLEM_DIR="$TEST_PROJECT/.golem"
  MISSION_DIR="${GOLEM_DIR}/missions"
}

# ─────────────────────────────────────────────────────────
# mission_init — 기본 생성
# ─────────────────────────────────────────────────────────

@test "mission: mission_init — 비어있지 않은 id 반환" {
  _source_mission
  local id
  id=$(mission_init "REST API 구현" "엔드포인트 3개" "외부 API 호출 없음" "UI 작업")
  [ -n "$id" ]
}

@test "mission: mission_init — id 가 msn_ 접두사로 시작" {
  _source_mission
  local id
  id=$(mission_init "인증 모듈" "JWT 발급" "DB 스키마 변경 없음" "결제 연동")
  [[ "$id" == msn_* ]]
}

@test "mission: mission_init — spec.md 생성" {
  _source_mission
  local id
  id=$(mission_init "테스트 목표" "기준" "제약" "비범위")
  [ -f "${MISSION_DIR}/${id}/spec.md" ]
}

@test "mission: mission_init — state.json 생성" {
  _source_mission
  local id
  id=$(mission_init "테스트 목표" "기준" "제약" "비범위")
  [ -f "${MISSION_DIR}/${id}/state.json" ]
}

@test "mission: mission_init — spec.md 에 목표 포함" {
  _source_mission
  local id
  id=$(mission_init "REST API 구현" "기준" "제약" "비범위")
  grep -q "REST API 구현" "${MISSION_DIR}/${id}/spec.md"
}

@test "mission: mission_init — spec.md 에 4개 섹션 헤더 존재 (목표/성공 기준/제약·범위/비범위)" {
  _source_mission
  local id spec
  id=$(mission_init "섹션 테스트" "성공 기준 텍스트" "제약 텍스트" "비범위 텍스트")
  spec="${MISSION_DIR}/${id}/spec.md"
  grep -q "^## 목표$" "$spec"
  grep -q "^## 성공 기준$" "$spec"
  grep -q "^## 제약·범위$" "$spec"
  grep -q "^## 비범위$" "$spec"
}

@test "mission: mission_init — state.json status=active" {
  _source_mission
  local id
  id=$(mission_init "활성 상태 테스트" "기준" "제약" "비범위")
  grep -q '"status":"active"' "${MISSION_DIR}/${id}/state.json"
}

@test "mission: mission_init — state.json 에 id 필드 포함" {
  _source_mission
  local id
  id=$(mission_init "id 필드 테스트" "기준" "제약" "비범위")
  grep -q "\"id\":\"${id}\"" "${MISSION_DIR}/${id}/state.json"
}

@test "mission: mission_init — state.json tasks 빈 배열" {
  _source_mission
  local id
  id=$(mission_init "빈 태스크" "기준" "제약" "비범위")
  grep -q '"tasks":\[\]' "${MISSION_DIR}/${id}/state.json"
}

# ─────────────────────────────────────────────────────────
# mission_set_tasks
# ─────────────────────────────────────────────────────────

@test "mission: mission_set_tasks — state.json 에 3개 태스크 생성" {
  _source_mission
  local id
  id=$(mission_init "태스크 설정 테스트" "기준" "제약" "비범위")
  mission_set_tasks "$id" "태스크A|태스크B|태스크C"

  local count
  count=$(grep -o '"idx":[0-9]*' "${MISSION_DIR}/${id}/state.json" | wc -l | tr -d ' ')
  [ "$count" -eq 3 ]
}

@test "mission: mission_set_tasks — 모든 태스크 status=pending" {
  _source_mission
  local id
  id=$(mission_init "pending 테스트" "기준" "제약" "비범위")
  mission_set_tasks "$id" "태스크1|태스크2|태스크3"

  local count
  count=$(grep -o '"status":"pending"' "${MISSION_DIR}/${id}/state.json" | wc -l | tr -d ' ')
  [ "$count" -eq 3 ]
}

@test "mission: mission_set_tasks — spec.md 에 3개 체크리스트 라인 생성" {
  _source_mission
  local id
  id=$(mission_init "체크리스트 테스트" "기준" "제약" "비범위")
  mission_set_tasks "$id" "항목1|항목2|항목3"

  local count
  count=$(grep -c "^- \[ \]" "${MISSION_DIR}/${id}/spec.md")
  [ "$count" -eq 3 ]
}

@test "mission: mission_set_tasks — spec.md 에 태스크 텍스트 포함" {
  _source_mission
  local id
  id=$(mission_init "텍스트 포함 테스트" "기준" "제약" "비범위")
  mission_set_tasks "$id" "첫번째 태스크|두번째 태스크|세번째 태스크"

  grep -q "첫번째 태스크" "${MISSION_DIR}/${id}/spec.md"
  grep -q "두번째 태스크" "${MISSION_DIR}/${id}/spec.md"
  grep -q "세번째 태스크" "${MISSION_DIR}/${id}/spec.md"
}

# ─────────────────────────────────────────────────────────
# mission_task — 상태 업데이트 + spec.md 체크박스
# ─────────────────────────────────────────────────────────

@test "mission: mission_task — idx 1 done 으로 업데이트" {
  _source_mission
  local id
  id=$(mission_init "task 업데이트 테스트" "기준" "제약" "비범위")
  mission_set_tasks "$id" "태스크A|태스크B|태스크C"
  mission_task "$id" 1 done ryn

  local obj
  obj=$(grep -o '{"idx":1,[^}]*}' "${MISSION_DIR}/${id}/state.json")
  echo "$obj" | grep -q '"status":"done"'
}

@test "mission: mission_task — soul 필드 ryn 으로 설정" {
  _source_mission
  local id
  id=$(mission_init "soul 설정 테스트" "기준" "제약" "비범위")
  mission_set_tasks "$id" "태스크A|태스크B|태스크C"
  mission_task "$id" 1 done ryn

  local obj
  obj=$(grep -o '{"idx":1,[^}]*}' "${MISSION_DIR}/${id}/state.json")
  echo "$obj" | grep -q '"soul":"ryn"'
}

@test "mission: mission_task — done 시 spec.md 체크박스 [x] 로 변경" {
  _source_mission
  local id
  id=$(mission_init "체크박스 테스트" "기준" "제약" "비범위")
  mission_set_tasks "$id" "태스크A|태스크B|태스크C"
  mission_task "$id" 1 done ryn

  grep -q "\- \[x\]" "${MISSION_DIR}/${id}/spec.md"
}

@test "mission: mission_task — in_progress 상태 설정" {
  _source_mission
  local id
  id=$(mission_init "in_progress 테스트" "기준" "제약" "비범위")
  mission_set_tasks "$id" "태스크A|태스크B|태스크C"
  mission_task "$id" 0 in_progress zen

  local obj
  obj=$(grep -o '{"idx":0,[^}]*}' "${MISSION_DIR}/${id}/state.json")
  echo "$obj" | grep -q '"status":"in_progress"'
}

@test "mission: mission_task — failed 상태 설정" {
  _source_mission
  local id
  id=$(mission_init "failed 테스트" "기준" "제약" "비범위")
  mission_set_tasks "$id" "태스크A|태스크B|태스크C"
  mission_task "$id" 2 failed kai

  local obj
  obj=$(grep -o '{"idx":2,[^}]*}' "${MISSION_DIR}/${id}/state.json")
  echo "$obj" | grep -q '"status":"failed"'
}

@test "mission: mission_task — done 이 아닌 경우 다른 태스크 체크박스는 [ ] 유지" {
  _source_mission
  local id
  id=$(mission_init "다른 태스크 체크박스 유지" "기준" "제약" "비범위")
  mission_set_tasks "$id" "태스크A|태스크B|태스크C"
  mission_task "$id" 0 done zen

  # 태스크B(idx 1), 태스크C(idx 2) 는 여전히 [ ]
  local unchecked
  unchecked=$(grep -c "^- \[ \]" "${MISSION_DIR}/${id}/spec.md")
  [ "$unchecked" -eq 2 ]
}

# ─────────────────────────────────────────────────────────
# mission_status
# ─────────────────────────────────────────────────────────

@test "mission: mission_status — 출력에 goal 포함" {
  _source_mission
  local id
  id=$(mission_init "상태 출력 테스트 목표" "기준" "제약" "비범위")
  mission_set_tasks "$id" "태스크A|태스크B|태스크C"

  run mission_status "$id"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "상태 출력 테스트 목표" ]]
}

@test "mission: mission_status — 진행도 카운트 출력 포함" {
  _source_mission
  local id
  id=$(mission_init "진행도 테스트" "기준" "제약" "비범위")
  mission_set_tasks "$id" "태스크A|태스크B|태스크C"
  mission_task "$id" 0 done zen

  run mission_status "$id"
  [ "$status" -eq 0 ]
  # 진행도: 1/3 형식 확인
  [[ "$output" =~ "1/3" ]]
}

@test "mission: mission_status — id 없이 호출 시 active 미션 반환" {
  _source_mission
  local id
  id=$(mission_init "자동 active 테스트" "기준" "제약" "비범위")

  run mission_status
  [ "$status" -eq 0 ]
  [[ "$output" =~ "자동 active 테스트" ]]
}

@test "mission: mission_status — 미션 없을 때 에러" {
  _source_mission

  run mission_status "msn_nonexistent_99999"
  [ "$status" -ne 0 ]
}

# ─────────────────────────────────────────────────────────
# mission_list
# ─────────────────────────────────────────────────────────

@test "mission: mission_list — 생성한 미션이 목록에 포함" {
  _source_mission
  local id
  id=$(mission_init "목록 테스트 미션" "기준" "제약" "비범위")

  run mission_list
  [ "$status" -eq 0 ]
  [[ "$output" =~ "$id" ]]
}

@test "mission: mission_list — 헤더 출력 포함" {
  _source_mission
  mission_init "헤더 테스트" "기준" "제약" "비범위" > /dev/null

  run mission_list
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Missions" ]]
}

@test "mission: mission_list — 미션 없어도 에러 없이 실행" {
  _source_mission

  run mission_list
  [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────────────────
# mission_complete
# ─────────────────────────────────────────────────────────

@test "mission: mission_complete — state.json status=completed 로 변경" {
  _source_mission
  local id
  id=$(mission_init "완료 테스트" "기준" "제약" "비범위")
  mission_complete "$id"

  grep -q '"status":"completed"' "${MISSION_DIR}/${id}/state.json"
}

@test "mission: mission_complete — active → completed 전환 후 active 아님" {
  _source_mission
  local id
  id=$(mission_init "active→completed 테스트" "기준" "제약" "비범위")
  mission_complete "$id"

  ! grep -q '"status":"active"' "${MISSION_DIR}/${id}/state.json"
}

@test "mission: mission_complete — 존재하지 않는 id → 에러" {
  _source_mission

  run mission_complete "msn_nonexistent_12345"
  [ "$status" -ne 0 ]
}

# ─────────────────────────────────────────────────────────
# 엣지케이스
# ─────────────────────────────────────────────────────────

@test "edge: mission_init — 빈 goal 로 호출해도 id 반환 (비어있지 않음)" {
  _source_mission
  local id
  id=$(mission_init "" "" "" "")
  # 빈 goal 이라도 id 는 생성돼야 한다
  [ -n "$id" ]
  [ -d "${MISSION_DIR}/${id}" ]
}

@test "edge: mission_init — 특수문자 포함 goal (쌍따옴표/백슬래시) 에서 state.json 유효" {
  _source_mission
  local id
  id=$(mission_init 'API "v2" 구현 & 테스트' "기준" "제약" "비범위")
  # state.json 이 존재하고 id 필드가 올바르게 들어가야 함
  [ -f "${MISSION_DIR}/${id}/state.json" ]
  grep -q "\"id\":\"${id}\"" "${MISSION_DIR}/${id}/state.json"
}

@test "edge: mission_task — 범위 초과 idx 는 에러 반환, state.json 오염 없음" {
  _source_mission
  local id
  id=$(mission_init "idx 초과 테스트" "기준" "제약" "비범위")
  mission_set_tasks "$id" "태스크A|태스크B|태스크C"

  # 원본 state.json 내용 저장
  local before
  before=$(cat "${MISSION_DIR}/${id}/state.json")

  # idx 99 → 없는 태스크이므로 에러(exit 1)
  run mission_task "$id" 99 done zen
  [ "$status" -ne 0 ]

  # state.json 이 변경되지 않아야 함
  local after
  after=$(cat "${MISSION_DIR}/${id}/state.json")
  [ "$before" = "$after" ]
}

@test "edge: mission_task — 잘못된 status 값 → 에러 반환" {
  _source_mission
  local id
  id=$(mission_init "잘못된 status 테스트" "기준" "제약" "비범위")
  mission_set_tasks "$id" "태스크A|태스크B|태스크C"

  run mission_task "$id" 0 invalid_status zen
  [ "$status" -ne 0 ]
}

@test "edge: mission_init — 동일 초 2회 호출 시 서로 다른 id 생성 (충돌 방지)" {
  _source_mission

  # RANDOM 접미사로 같은 초 내에도 충돌 없이 서로 다른 id 생성돼야 한다
  local id1 id2
  id1=$(mission_init "첫번째 미션" "기준" "제약" "비범위")
  id2=$(mission_init "두번째 미션" "기준" "제약" "비범위")
  [ "$id1" != "$id2" ]
}

@test "edge: mission_init — 두 미션 모두 디렉터리 생성됨" {
  _source_mission
  local id1 id2
  id1=$(mission_init "미션 1" "기준" "제약" "비범위")
  id2=$(mission_init "미션 2" "기준" "제약" "비범위")

  [ -d "${MISSION_DIR}/${id1}" ]
  [ -d "${MISSION_DIR}/${id2}" ]
}

@test "edge: mission_set_tasks — 존재하지 않는 id → 에러" {
  _source_mission

  run mission_set_tasks "msn_nonexistent_00001" "태스크A|태스크B"
  [ "$status" -ne 0 ]
}

@test "edge: mission_complete 후 mission_list 에 completed 상태로 표시" {
  _source_mission
  local id
  id=$(mission_init "완료 후 목록 테스트" "기준" "제약" "비범위")
  mission_complete "$id"

  run mission_list
  [ "$status" -eq 0 ]
  [[ "$output" =~ "completed" ]]
}
