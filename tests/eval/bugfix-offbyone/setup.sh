#!/usr/bin/env bash
# 픽스처: off-by-one 버그가 있는 count.sh
ws="$1"
cat > "${ws}/count.sh" <<'EOF'
#!/bin/bash
# count.sh <n> — 1부터 n까지 한 줄에 하나씩 출력해야 한다
n="$1"
i=0
while [ "$i" -lt "$n" ]; do
  echo "$i"
  i=$((i + 1))
done
EOF
