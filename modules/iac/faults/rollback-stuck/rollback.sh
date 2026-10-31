#!/bin/bash
# iac rollback-stuck — rollback. 외부 의존 설정을 v1 허용으로 되돌리고 롤백을 이어서 끝낸다. 수동 SG 삭제.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
need_stack
B=$(sres ArtifactBucket)
aws ssm put-parameter --name /opslab/iac/dependency --type String --overwrite --value ready >/dev/null && echo "  /opslab/iac/dependency=ready"
printf '{"allowed": ["v1", "v2"]}' | aws s3 cp - "s3://$B/config/allowed.json" --quiet && echo "  config/allowed.json = v1,v2"
if [ "$(stack_status)" = UPDATE_ROLLBACK_FAILED ]; then
  aws cloudformation continue-update-rollback --stack-name "$STACK" && echo "  롤백 계속: $(wait_stack 1200)"
fi
sg=$(aws ec2 describe-security-groups --filters Name=group-name,Values="$SID-iac-admin-sg-new" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
[ -n "$sg" ] && [ "$sg" != None ] && [ "$sg" != "$(sres AdminSg)" ] && aws ec2 delete-security-group --group-id "$sg" && echo "  수동 SG 삭제"
