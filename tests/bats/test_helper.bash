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
  export GOLEM_PROJECT="$TEST_PROJECT"
  # GOLEM_ROOT는 tests/bats/ 기준 두 단계 위 (프로젝트 루트)
  export GOLEM_ROOT
  GOLEM_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

  mkdir -p "$TEST_PROJECT/.golem/souls"
  mkdir -p "$TEST_PROJECT/.golem/growth-log"
  mkdir -p "$TEST_PROJECT/.golem/mailbox"
}

teardown() {
  if [[ -n "${TEST_PROJECT:-}" && -d "$TEST_PROJECT" ]]; then
    rm -rf "$TEST_PROJECT"
  fi
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
