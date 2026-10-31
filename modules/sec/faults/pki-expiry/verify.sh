#!/bin/bash
# sec pki-expiry 판정 — 내부 HTTPS 검증, 인증서 남은 기간, PKI 역할, 앱 정책. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start pki-expiry
echo "[1] 내부 HTTPS"; chk_tls
out=$(arun "openssl x509 -in /etc/nginx/tls/app.pem -noout -checkend 3600 >/dev/null && echo ok || echo expiring" 30)
[ "$(grep -c '^ok' <<<"$out")" = "$(wc -w <<<"$(app_ids)")" ] && ok "모든 앱 서버 인증서 1시간 이상 남음" || ng "1시간 안에 만료되는(또는 만료된) 인증서 있음"
echo "[2] 발급 설정"; chk_agent; chk_vpolicy
m=$(vrun "vault read -field=max_ttl pki/roles/internal" 30 | tr -dc 0-9)
[ "${m:-0}" -ge 86400 ] 2>/dev/null && ok "PKI 역할 max_ttl ${m}s" || ng "PKI 역할 max_ttl ${m:-?}s (24시간 이상이어야 함)"
finish
