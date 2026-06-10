# Mission: lib/mission.sh에 mission_next <id> 함수 추가 — 첫 pending 태스크 반환

> id: msn_1780583001_10881 · created: 2026-06-04T14:23:21

## 목표
lib/mission.sh에 mission_next <id> 함수 추가 — 첫 pending 태스크 반환

## 성공 기준
mission_next가 첫 pending 태스크의 idx와 text 출력; pending 없으면 none; bats 테스트 통과

## 제약·범위
bash, jq 미사용, _sed_i 사용, 기존 스타일 유지

## 비범위
forge.sh verb 노출 제외, UI 제외

## 태스크
- [x] mission_next 함수 구현 (Ryn)
- [x] bats 테스트 작성·실행으로 검증 (Zen, author≠verifier)
