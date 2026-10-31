#!/bin/bash
# sec transit-rotate — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: Vault Transit 키 orders(새 버전 추가·최소 복호화 버전) 또는 Vault 앱 정책(app)
vneed
V_=$(pick_variant 2)
case $V_ in
  1) vrun "vault write -f transit/keys/orders/rotate >/dev/null
L=\$(vault read -field=latest_version transit/keys/orders)
vault write transit/keys/orders/config min_decryption_version=\$L >/dev/null && echo ok" 30 | grep -q ok ;;
  2) vrun "vault write -f transit/keys/orders/rotate >/dev/null && echo ok" 30 | grep -q ok &&
     put_app_policy "$(grep -v 'transit/decrypt' <<<"$APP_VAULT_POLICY")" >/dev/null ;;
esac || exit 1
record $V_
