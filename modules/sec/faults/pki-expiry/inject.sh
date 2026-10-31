#!/bin/bash
# sec pki-expiry — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: Vault PKI 역할(pki/roles/internal)·발급자(issuer)·앱 정책, 앱 서버의 인증서 파일과 Agent 재시작
vneed
V_=$(pick_variant 2)
case $V_ in
  1) # 인증서 최대 기간을 2분으로 줄여 재발급받게 한 뒤, 정책 정리로 Agent 가 갱신하지 못하게 함 → 2분 뒤 만료
     vrun "vault write pki/roles/internal allow_any_name=true allow_ip_sans=true max_ttl=2m >/dev/null && echo ok" 30 | grep -q ok &&
     arun "rm -f /etc/nginx/tls/app.pem; systemctl restart vault-agent; for i in \$(seq 1 20); do [ -s /etc/nginx/tls/app.pem ] && break; sleep 1; done; echo done" 60 | grep -q done &&
     put_app_policy "$(grep -v 'pki/issue' <<<"$APP_VAULT_POLICY")" >/dev/null ;;
  2) # 새 루트 CA(root-2)를 만들어 기본 발급자로 바꾸고 재발급 → 클라이언트가 가진 CA(root-1)로는 검증 실패
     vrun "vault read pki/issuer/root-2 >/dev/null 2>&1 || vault write pki/root/generate/internal common_name='opslab internal CA 2' issuer_name=root-2 ttl=87600h >/dev/null
vault write pki/config/issuers default=root-2 >/dev/null && echo ok" 60 | grep -q ok &&
     arun "rm -f /etc/nginx/tls/app.pem; systemctl restart vault-agent; for i in \$(seq 1 20); do [ -s /etc/nginx/tls/app.pem ] && break; sleep 1; done; echo done" 60 | grep -q done ;;
esac || exit 1
record $V_
