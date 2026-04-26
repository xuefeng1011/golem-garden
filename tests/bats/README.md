# GolemGarden Bash 테스트 (bats-core)

forge.sh + lib/*.sh 회귀 검출을 위한 bats 테스트 인프라.

## 빠른 실행

```bash
bash tests/bats/run.sh
```

## 버전 확인

```bash
bash tests/bats/run.sh --version
# Bats 1.11.0
```

## 특정 파일만 실행

```bash
bash tests/bats/bats-core/bin/bats tests/bats/test_soul_parser.bats
```

## 구조

```
tests/bats/
  bats-core/              벤더링된 bats-core v1.11.0 (수동 갱신 필요)
  test_helper.bash        공용 setup/teardown, load_fixture, assert helpers
  test_soul_parser.bats   lib/soul-parser.sh 테스트 (Zen 작성)
  test_growth_log.bats    lib/growth-log.sh 테스트 (Zen 작성)
  test_rank_system.bats   lib/rank-system.sh 테스트 (Zen 작성)
  fixtures/
    souls/                테스트용 SOUL frontmatter 샘플 (nex, bolt, zen)
    growth-log/           테스트용 JSONL 샘플
```

## Helper API (test_helper.bash)

| 함수 | 설명 |
|------|------|
| `setup()` | 격리 임시 GOLEM_PROJECT 생성, GOLEM_ROOT 설정 |
| `teardown()` | 임시 디렉토리 정리 |
| `load_fixture "path" "dest"` | fixtures/ 에서 TEST_PROJECT로 파일 복사 |
| `assert_file_contains "file" "pattern"` | 파일에 패턴 포함 여부 확인 |
| `assert_jsonl_field "file" "field" "val"` | JSONL 필드 값 확인 |

## 포터빌리티

| 환경 | 상태 |
|------|------|
| Windows Git Bash | PASS (검증됨) |
| macOS | PASS (mktemp 호환 방식 사용) |
| Linux | PASS |

- `mktemp -d "${TMPDIR:-/tmp}/golem-bats-XXXXXX"` : GNU/BSD 양쪽 호환
- `TMPDIR:-/tmp` fallback : Windows Git Bash 환경변수 미설정 대비

## bats-core 갱신 방법

```bash
# 새 버전 릴리스 시 수동 갱신
rm -rf tests/bats/bats-core
curl -fsSL "https://github.com/bats-core/bats-core/archive/refs/tags/vX.Y.Z.tar.gz" -o /tmp/bats.tar.gz
tar -xzf /tmp/bats.tar.gz -C tests/bats/
mv tests/bats/bats-core-X.Y.Z tests/bats/bats-core
rm /tmp/bats.tar.gz
```

## CI 연동 (후속 PR)

```yaml
# .github/workflows/test-bash.yml (예시)
- name: Run bats tests
  run: bash tests/bats/run.sh
```
