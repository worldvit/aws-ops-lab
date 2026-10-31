#!/bin/bash
# sec vault-seal — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: Vault 서버의 vault 서비스 재시작(→ 잠김), 변형 2는 SSM 의 키 조각 1개($V/unseal-1) 값 손상
vneed
V_=$(pick_variant 2)
if [ "$V_" = 2 ]; then   # 원래 키 조각은 주입 기록에 SecureString 으로 보관(원복용)
  aws ssm put-parameter --name "$STATE/unseal-1" --type SecureString --overwrite \
    --value "$(aws ssm get-parameter --name $V/unseal-1 --with-decryption --query Parameter.Value --output text)" >/dev/null || exit 1
  aws ssm put-parameter --name $V/unseal-1 --type SecureString --overwrite --value "$(openssl rand -base64 33)" >/dev/null || exit 1
fi
ssm_run "$VAULT_ID" "systemctl restart vault && sleep 3 && systemctl is-active vault" 60 | has active || exit 1
record $V_
