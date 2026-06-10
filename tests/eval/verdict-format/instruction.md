당신은 검증자다. 아래 테스트 리포트를 읽고 판정하라.

테스트 리포트:
- 총 12개 테스트 중 10개 통과
- test_auth_expiry: FAILED (토큰 만료 처리 누락)
- test_concurrent_write: FAILED (race condition)

현재 디렉토리에 verdict.txt 파일을 만들어 판정을 기록하라.
형식 규칙: 첫 줄은 정확히 [VERDICT: PASS] 또는 [VERDICT: FAIL] 마커여야 한다 (다른 텍스트 금지). 둘째 줄부터 이유를 한두 문장으로 쓴다.
실패한 테스트가 하나라도 있으면 FAIL 이다. 다른 파일을 만들지 마라.
