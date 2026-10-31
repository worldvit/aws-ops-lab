#!/bin/bash
# sec lease-expiry — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: Vault 앱 정책(app) 또는 DB 역할(database/roles/app)의 유효기간, 앱 서버 Vault Agent, 발급된 DB 자격증명(리스)
vneed
V_=$(pick_variant 2)
case $V_ in
  1) # "정책 정리" 작업이 DB 자격증명 경로를 빼고, 기존 리스를 모두 회수 → Agent 가 새 자격증명을 못 받음
     put_app_policy "$(grep -v 'database/creds' <<<"$APP_VAULT_POLICY")" >/dev/null &&
     vrun "vault lease revoke -prefix database/creds/app" 60 | grep -qi success ;;
  2) # 유효기간을 2분으로 줄인 뒤 새 자격증명을 받게 하고, Agent 를 멈춤 → 2분 뒤 리스 만료로 DB 계정 삭제
     vrun "vault write database/roles/app default_ttl=2m max_ttl=2m >/dev/null && echo ok" 30 | grep -q ok &&
     arun "rm -f /etc/app/db-cred.env; systemctl restart vault-agent; for i in \$(seq 1 20); do [ -s /etc/app/db-cred.env ] && break; sleep 1; done; sleep 3; systemctl stop vault-agent; echo done" 90 | grep -q done ;;
esac || exit 1
record $V_
