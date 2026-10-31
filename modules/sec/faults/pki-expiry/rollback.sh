#!/bin/bash
# sec pki-expiry — rollback. PKI 역할·기본 발급자·정책 원복 후 인증서 재발급.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
vneed
put_app_policy >/dev/null && echo "  Vault 앱 정책(app) 원본으로"
vrun "vault write pki/roles/internal allow_any_name=true allow_ip_sans=true max_ttl=72h >/dev/null && echo '  PKI 역할 max_ttl 72h'
vault write pki/config/issuers default=root-1 >/dev/null && echo '  기본 발급자 root-1'" 30
arun "rm -f /etc/nginx/tls/app.pem; systemctl enable -q vault-agent; systemctl restart vault-agent; for i in \$(seq 1 20); do [ -s /etc/nginx/tls/app.pem ] && break; sleep 1; done; systemctl reload nginx 2>/dev/null; echo \$(hostname) cert=\$(openssl x509 -in /etc/nginx/tls/app.pem -noout -enddate 2>/dev/null | cut -d= -f2)" 60 | sed 's/^/  /'
