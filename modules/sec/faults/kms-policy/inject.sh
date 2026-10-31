#!/bin/bash
# sec kms-policy — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: KMS 키($KEY_ALIAS)의 키 정책 중 앱 역할 관련 문장만. 관리(Admin) 문장은 건드리지 않는다(잠김 방지).
K=$(aws kms describe-key --key-id "$KEY_ALIAS" --query KeyMetadata.KeyId --output text 2>/dev/null) || exit 3
P=$(aws kms get-key-policy --key-id "$K" --policy-name default --query Policy --output text) || exit 1
save policy "$P"
V_=$(pick_variant 2)
case $V_ in
  1) N=$(jq -c '.Statement |= map(select(.Sid != "AppUse"))' <<<"$P") ;;
  2) N=$(jq -c --arg r "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/$APP_ROLE" \
       '.Statement += [{"Sid":"DenyDecryptOutsideBatch","Effect":"Deny","Principal":{"AWS":$r},"Action":"kms:Decrypt","Resource":"*",
         "Condition":{"StringNotEquals":{"aws:PrincipalTag/batch":"true"}}}]' <<<"$P") ;;
esac
aws kms put-key-policy --key-id "$K" --policy-name default --policy "$N" || exit 1
record $V_
