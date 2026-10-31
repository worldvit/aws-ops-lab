#!/bin/bash
# sec iam-error — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: 앱 역할($APP_ROLE)의 인라인 정책만($APP_POLICY_NAME 수정·삭제, $SID-sec-guardrail 추가). 관리형 정책은 건드리지 않는다.
D_=$(aws iam get-role-policy --role-name "$APP_ROLE" --policy-name "$APP_POLICY_NAME" --query PolicyDocument --output json) || exit 3
save doc "$(jq -c . <<<"$D_")"
V_=$(pick_variant 3)
case $V_ in
  1) aws iam delete-role-policy --role-name "$APP_ROLE" --policy-name "$APP_POLICY_NAME" ;;
  2) aws iam put-role-policy --role-name "$APP_ROLE" --policy-name "$SID-sec-guardrail" --policy-document \
       '{"Version":"2012-10-17","Statement":[{"Sid":"DenySecretsOutsideVpce","Effect":"Deny","Action":"secretsmanager:GetSecretValue","Resource":"*","Condition":{"StringNotEquals":{"aws:SourceVpce":"vpce-00000000"}}}]}' ;;
  3) aws iam put-role-policy --role-name "$APP_ROLE" --policy-name "$APP_POLICY_NAME" --policy-document \
       "$(jq -c '.Statement[0].Resource |= sub("secret:(?<n>[^:]*)/app"; "secret:\(.n)/app-prod")' <<<"$D_")" ;;
esac || exit 1
record $V_
