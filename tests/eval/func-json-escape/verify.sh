#!/usr/bin/env bash
ws="$1"
[ -f "${ws}/lib.sh" ] || exit 1
# shellcheck source=/dev/null
source "${ws}/lib.sh" || exit 1
out=$(json_escape 'a"b\c')
[ "$out" = 'a\"b\\c' ] || exit 1
out2=$(json_escape 'plain')
[ "$out2" = 'plain' ] || exit 1
exit 0
