#!/bin/bash
# sec iam-error — rollback. 거부 정책 삭제, 인라인 정책을 주입 전 문서로.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
aws iam delete-role-policy --role-name "$APP_ROLE" --policy-name "$SID-sec-guardrail" 2>/dev/null && echo "  거부 정책 $SID-sec-guardrail 삭제"
D_=$(load doc)
if [ -z "$D_" ] || [ "$D_" = None ]; then
  A=$(aws secretsmanager describe-secret --secret-id "$SECRET_ID" --query ARN --output text)
  D_="{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"ReadAppSecret\",\"Effect\":\"Allow\",\"Action\":\"secretsmanager:GetSecretValue\",\"Resource\":\"$A\"}]}"
fi
aws iam put-role-policy --role-name "$APP_ROLE" --policy-name "$APP_POLICY_NAME" --policy-document "$D_" && echo "  인라인 정책 $APP_POLICY_NAME 원복"
wait_app /secret 300
