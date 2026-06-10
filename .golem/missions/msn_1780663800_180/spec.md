# Mission: 리뷰 발견 데이터손상·안전한계 수정 (mission dogfood)

> id: msn_1780663800_180 · created: 2026-06-05T12:50:00

## 목표
리뷰 발견 데이터손상·안전한계 수정 (mission dogfood)

## 성공 기준
mission.sh JSON 손상 4건(따옴표 task/goal·비숫자 idx·슬래시) 수정; maxTurns/disallowedTools 실제 적용 또는 문서 정정; 각 손상을 잡는 음성 bats 테스트 추가; 전체 스위트 통과

## 제약·범위
기존 _json_escape/_sed_i 재사용; 배열 재생성 방식으로 통일; 출력동작 불변; jq 미사용

## 비범위
soul_to_omc_agent 마이그레이션은 다음 작업으로 연기; UI 제외

## 태스크
- [x] mission.sh JSON 손상 클러스터 수정 — 배열 재생성·idx 검증·원자적 쓰기 (Ryn)
- [x] agent-runner.sh maxTurns/disallowedTools 적용 또는 문서 정정 + 멀티블록 텍스트 추출 (Ryn)
- [x] 음성 bats 테스트 — 따옴표·슬래시·비숫자 idx로 손상 재현·차단 검증 (Zen, author 아님)
- [x] 전체 스위트 + 손상 시나리오 독립 검증 (Director)
