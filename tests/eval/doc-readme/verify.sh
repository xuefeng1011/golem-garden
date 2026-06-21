#!/usr/bin/env bash
ws="$1"
f="${ws}/README.md"
[ -f "$f" ] || exit 1
[ "$(head -1 "$f" | tr -d '\r')" = "# Widget" ] || exit 1
grep -q '^## Install' "$f" || exit 1
grep -q '^## Usage' "$f" || exit 1
grep -q '^```bash' "$f" || exit 1
# Install 이 Usage 보다 먼저
install_line=$(grep -n '^## Install' "$f" | head -1 | cut -d: -f1)
usage_line=$(grep -n '^## Usage' "$f" | head -1 | cut -d: -f1)
[ "$install_line" -lt "$usage_line" ] || exit 1
exit 0
