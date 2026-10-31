#!/bin/bash
# sec lease-expiry — rollback. 정책·유효기간 원복, Agent 재시작으로 새 자격증명 발급.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
vneed
put_app_policy >/dev/null && echo "  Vault 앱 정책(app) 원본으로"
vrun "vault write database/roles/app default_ttl=1h max_ttl=24h >/dev/null && echo '  DB 역할 유효기간 1h/24h'" 30
arun "rm -f /etc/app/db-cred.env; systemctl enable -q vault-agent; systemctl restart vault-agent; for i in \$(seq 1 20); do [ -s /etc/app/db-cred.env ] && break; sleep 1; done; echo \$(hostname) agent=\$(systemctl is-active vault-agent) cred=\$([ -s /etc/app/db-cred.env ] && echo ok || echo 없음)" 90 | sed 's/^/  /'
