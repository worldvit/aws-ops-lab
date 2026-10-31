#!/bin/bash
# sec transit-rotate — rollback. 최소 복호화 버전 1, 정책 원복(늘어난 키 버전은 그대로 둔다 — 지울 필요 없음).
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
vneed
vrun "vault write transit/keys/orders/config min_decryption_version=1 >/dev/null && echo '  min_decryption_version=1'" 30
put_app_policy >/dev/null && echo "  Vault 앱 정책(app) 원본으로"
