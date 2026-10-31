#!/bin/bash
# sec 정상 상태 정의(2단계) 판정. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../check.sh"
start baseline
echo "[1] Vault"; chk_vault; chk_vpolicy
echo "[2] 앱 기능"
chk_app /db "DB 쓰기(/db) — Vault 동적 자격증명"
chk_app /note "메모(/note) — Vault Transit 암호화·복호화"
chk_app /secret "비밀 읽기(/secret) — Secrets Manager + KMS"
echo "[3] 앱 서버"; chk_agent; chk_tls
echo "[4] 인증서 남은 기간"
out=$(arun "openssl x509 -in /etc/nginx/tls/app.pem -noout -checkend 3600 >/dev/null && echo ok || echo expiring" 30)
[ "$(grep -c '^ok' <<<"$out")" = "$(wc -w <<<"$(app_ids)")" ] && ok "모든 앱 서버 인증서 1시간 이상 남음" || ng "1시간 안에 만료되는 인증서 있음"
finish
