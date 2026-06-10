#!/bin/bash
# setup.sh — 중복 블록이 3개 있는 동작하는 process.sh 생성
ws="$1"
cat > "${ws}/process.sh" <<'SCRIPT'
#!/bin/bash
# process.sh — 레코드 3개를 검증·포맷하여 출력한다

# 레코드 alpha 처리
name="alpha"; val=42
if [ "$val" -ge 0 ] && [ "$val" -le 999 ]; then tag="ok"; else tag="err"; fi
printf '[%s|%05d|%s]\n' "$name" "$val" "$tag"

# 레코드 beta 처리
name="beta"; val=0
if [ "$val" -ge 0 ] && [ "$val" -le 999 ]; then tag="ok"; else tag="err"; fi
printf '[%s|%05d|%s]\n' "$name" "$val" "$tag"

# 레코드 gamma 처리
name="gamma"; val=1000
if [ "$val" -ge 0 ] && [ "$val" -le 999 ]; then tag="ok"; else tag="err"; fi
printf '[%s|%05d|%s]\n' "$name" "$val" "$tag"
SCRIPT
chmod +x "${ws}/process.sh"
