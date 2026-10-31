#!/bin/bash
# sec kms-policy — rollback. 주입 전 키 정책으로 되돌린다(주입 기록이 없으면 AppUse 문장을 다시 넣고 Deny 문장을 뺀다).
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
K=$(aws kms describe-key --key-id "$KEY_ALIAS" --query KeyMetadata.KeyId --output text 2>/dev/null) || exit 3
P=$(load policy)
if [ -z "$P" ] || [ "$P" = None ]; then
  R="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/$APP_ROLE"
  P=$(aws kms get-key-policy --key-id "$K" --policy-name default --query Policy --output text | jq -c --arg r "$R" \
    '.Statement |= map(select(.Effect != "Deny" and .Sid != "AppUse")) | .Statement += [{"Sid":"AppUse","Effect":"Allow","Principal":{"AWS":$r},"Action":["kms:Decrypt","kms:DescribeKey"],"Resource":"*"}]')
fi
aws kms put-key-policy --key-id "$K" --policy-name default --policy "$P" && echo "  키 정책 원복"
