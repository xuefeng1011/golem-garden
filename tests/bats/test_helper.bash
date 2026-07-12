#!/usr/bin/env bash
# test_helper.bash — GolemGarden bats 공용 setup/teardown
# Zen이 작성하는 .bats 파일에서 load "test_helper" 로 임포트

# --------------------------------------------------------------------------
# setup / teardown — 각 테스트마다 격리된 임시 GOLEM_PROJECT 생성
# --------------------------------------------------------------------------
setup() {
  # GNU mktemp: -t prefix.XXXXXX
  # BSD (macOS) mktemp: -t prefix (suffix는 자동)
  # 두 형식 모두 지원하는 호환 방식: -t 없이 전체 패턴 지정
  TEST_PROJECT="$(mktemp -d "${TMPDIR:-/tmp}/golem-bats-XXXXXX")"
  # Windows Git Bash: TMPDIR 이 'C:/...' 형태면 TEST_PROJECT 도 콜론을 포함해
  # PATH="$TEST_PROJECT/bin:$PATH" 프리펜드가 오파싱된다(fake claude 미발견 → 행).
  # cd+pwd 로 POSIX 형태(/c/...)로 정규화 — 다른 용도에는 양쪽 형태 모두 무해.
  TEST_PROJECT="$(cd "$TEST_PROJECT" && pwd)"
  export GOLEM_PROJECT="$TEST_PROJECT"
  # GOLEM_ROOT는 tests/bats/ 기준 두 단계 위 (프로젝트 루트)
  export GOLEM_ROOT
  GOLEM_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  # GOLEM_DIR: lib/growth-log.sh가 source 시 ${GOLEM_DIR:-${GOLEM_ROOT}} 분기를 탐
  # 반드시 TEST_PROJECT 기반으로 고정해야 글로벌 growth-log/ 누설을 차단한다
  export GOLEM_DIR="$TEST_PROJECT/.golem"
  export GROWTH_DIR="$TEST_PROJECT/.golem/growth-log"

  mkdir -p "$TEST_PROJECT/.golem/souls"
  mkdir -p "$TEST_PROJECT/.golem/growth-log"
  mkdir -p "$TEST_PROJECT/.golem/mailbox"
}

teardown() {
  if [[ -n "${TEST_PROJECT:-}" && -d "$TEST_PROJECT" ]]; then
    rm -rf "$TEST_PROJECT"
  fi
  unset GOLEM_DIR GROWTH_DIR
}

# --------------------------------------------------------------------------
# golem_load_lib — lib을 source한 후 격리 변수를 반드시 재설정
# lib/growth-log.sh 등은 source 시 GROWTH_DIR을 덮어쓰므로,
# source 후에도 TEST_PROJECT 기반 격리를 보장해야 한다.
#
# 사용법:
#   golem_load_lib growth-log
#   golem_load_lib soul-parser
# --------------------------------------------------------------------------
golem_load_lib() {
  local lib_name="$1"
  # shellcheck source=/dev/null
  source "${GOLEM_ROOT}/lib/${lib_name}.sh"
  # source 후 덮어쓰인 GROWTH_DIR을 격리 값으로 재설정
  export GOLEM_DIR="$TEST_PROJECT/.golem"
  export GROWTH_DIR="$TEST_PROJECT/.golem/growth-log"
}

# --------------------------------------------------------------------------
# load_fixture — fixture 파일을 TEST_PROJECT 내 경로로 복사
#
# 사용법:
#   load_fixture "souls/nex.md"  "$TEST_PROJECT/.golem/souls/nex.md"
#   load_fixture "growth-log/sample.jsonl" "$TEST_PROJECT/.golem/growth-log/nex.jsonl"
# --------------------------------------------------------------------------
load_fixture() {
  local name="$1"
  local dest="$2"
  local src="${BATS_TEST_DIRNAME}/fixtures/${name}"

  if [[ ! -f "$src" ]]; then
    echo "load_fixture: fixture not found: $src" >&2
    return 1
  fi

  # 목적지 디렉토리 보장
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
}

# --------------------------------------------------------------------------
# assert_file_contains — 파일에 특정 문자열이 포함되어 있는지 확인
# --------------------------------------------------------------------------
assert_file_contains() {
  local file="$1"
  local pattern="$2"
  if ! grep -q "$pattern" "$file" 2>/dev/null; then
    echo "assert_file_contains: '$pattern' not found in $file" >&2
    cat "$file" >&2
    return 1
  fi
}

# --------------------------------------------------------------------------
# assert_jsonl_field — JSONL 파일에서 특정 필드 값 확인
# 사용법: assert_jsonl_field "file.jsonl" "result" "success"
# --------------------------------------------------------------------------
assert_jsonl_field() {
  local file="$1"
  local field="$2"
  local expected="$3"
  if ! grep -q "\"${field}\":\"${expected}\"" "$file" 2>/dev/null; then
    echo "assert_jsonl_field: field='$field' expected='$expected' not found in $file" >&2
    cat "$file" >&2
    return 1
  fi
}
