#!/usr/bin/env bash
# json-lite.sh — escape-aware 경량 JSON 문자열 헬퍼 (jq 불사용, 공용)
#
# mission.sh 에서 추출 (P3 계약 경화) — mission.sh · flow-contract.sh 가 공용
# 소싱한다. quote-naive `grep -o '"key":"[^"]*"'` 가 값 내부의 이스케이프된
# `\"` 에서 잘리던 데이터 손상 버그를 막는 escape-aware 구현.
#
# 제공 함수:
#   _json_get_string <json_line> <key>  — RAW(이스케이프된) 문자열 값 추출
#   _json_unescape  <raw_string>        — 표시용 디코드 (\n \t \" \\ …)
#   _json_scalar    <json_line> <key>   — 이스케이프 없는 scalar (id/status 등)

# JSON 문자열 값 추출 (escape-aware) — `\([^"\\]\|\\.\)*` 와 동등한 문자 워커.
# 출력은 RAW(이스케이프된) JSON 문자열 — 표시용으로는 _json_unescape 를 거친다.
# _json_get_string <json_line> <key>
_json_get_string() {
  printf '%s' "$1" | awk -v key="$2" '
  {
    pat = "\"" key "\":\""
    plen = length(pat)
    n = length($0)
    i = 1
    while (i <= n - plen + 1) {
      if (substr($0, i, plen) == pat) {
        i += plen
        out = ""
        while (i <= n) {
          c = substr($0, i, 1)
          if (c == "\\") {
            if (i < n) { d = substr($0, i+1, 1); out = out c d; i += 2; continue }
          } else if (c == "\"") { printf "%s", out; exit 0 }
          out = out c; i++
        }
        exit 0
      }
      i++
    }
  }'
}

# _json_escape 의 역연산 — 표시용 디코드 (\\n→개행, \\t→탭, \\\"→\", \\\\→\\)
# 순서 중요: 백슬래시 시퀀스를 먼저 해석하되 \\\\ 는 마지막에 풀어 이중 해석 방지.
# _json_unescape <raw_json_string>
_json_unescape() {
  printf '%s' "$1" | awk '
    {
      out=""
      n=length($0)
      i=1
      while (i<=n) {
        c=substr($0,i,1)
        if (c=="\\" && i<n) {
          d=substr($0,i+1,1)
          if (d=="n")      { out=out "\n"; i+=2; continue }
          else if (d=="t") { out=out "\t"; i+=2; continue }
          else if (d=="r") { out=out "\r"; i+=2; continue }
          else if (d=="\""){ out=out "\""; i+=2; continue }
          else if (d=="\\"){ out=out "\\"; i+=2; continue }
          else if (d=="/") { out=out "/";  i+=2; continue }
          else             { out=out d;    i+=2; continue }
        }
        out=out c; i++
      }
      printf "%s", out
    }'
}

# 단일 JSON scalar 필드(이스케이프 없는 id/status/created/seq 등) 추출.
# _json_scalar <json_line> <key>
_json_scalar() {
  grep -o "\"$2\":\"[^\"]*\"" <<<"$1" | head -1 | sed "s/\"$2\":\"//;s/\"$//"
}

# JSON 배열의 top-level 원소를 한 줄에 하나씩 출력 (escape-aware, 1-depth 계약)
# 문자열 내부의 ,·]·} 는 분리 기준이 되지 않는다 — flow-contract 의 `},{`
# 리터럴 분할 취약점을 회피하는 문자 단위 워커.
#
# mission.sh 에서 승격(P3 공용화) — _mission_json_array_items 는 이 함수의
# 얇은 back-compat 별칭으로 남아있다. 입력 문자열 어디든 첫 `[` 를 기준점으로
# 잡으므로, `"key":[...]` 형태의 부분 문자열(뒤에 다른 키가 이어져도 무방)을
# 그대로 넘겨도 해당 배열만 정확히 추출한다.
# _json_array_items <stdin: JSON 텍스트(전체 또는 "key":[...] 부분 문자열)>
_json_array_items() {
  awk '
  { s = s $0 }
  END {
    n = length(s)
    i = index(s, "[")
    if (i == 0) exit 1
    depth = 0; instr = 0; buf = ""
    for (; i <= n; i++) {
      c = substr(s, i, 1)
      if (instr) {
        buf = buf c
        if (c == "\\") { i++; buf = buf substr(s, i, 1); continue }
        if (c == "\"") instr = 0
        continue
      }
      if (c == "\"") { instr = 1; buf = buf c; continue }
      if (c == "[" || c == "{") { depth++; if (c == "[" && depth == 1) continue }
      if (c == "]" || c == "}") {
        depth--
        if (c == "]" && depth == 0) { if (buf != "") print buf; break }
      }
      if (c == "," && depth == 1) { if (buf != "") print buf; buf = ""; continue }
      if (depth >= 1) buf = buf c
    }
  }'
}
