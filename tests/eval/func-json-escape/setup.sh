#!/usr/bin/env bash
# 픽스처: json_escape 가 비어 있는 lib.sh
ws="$1"
cat > "${ws}/lib.sh" <<'EOF'
#!/bin/bash
# lib.sh — 문자열 유틸

# json_escape <string> — JSON 문자열 값으로 안전하게 이스케이프해 출력
json_escape() {
  : # TODO: 구현
}
EOF
