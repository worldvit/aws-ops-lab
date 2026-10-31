#!/bin/bash
# iac update-fail — rollback. 충돌한 수동 리소스를 지우고 릴리스 v2 를 완료한다(원래 하려던 배포).
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
need_stack
sg=$(aws ec2 describe-security-groups --filters Name=group-name,Values="$SID-iac-admin-sg-v2" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
[ -n "$sg" ] && [ "$sg" != None ] && [ "$sg" != "$(sres AdminSg)" ] && aws ec2 delete-security-group --group-id "$sg" && echo "  수동 SG 삭제"
for r in $(aws elbv2 describe-rules --listener-arn "$(listener_arn)" --query "Rules[?Priority=='20'].RuleArn" --output text); do
  [ "$r" != "$(sres PromoRule)" ] && aws elbv2 delete-rule --rule-arn "$r" && echo "  수동 리스너 규칙(우선순위 20) 삭제"
done
V_=$(load variant)
if [ "$V_" = 2 ]; then deploy_app PromoText=v2 RulePriority=20; else deploy_app PromoText=v2 AdminSgName="$SID-iac-admin-sg-v2"; fi
echo "  릴리스 v2 배포: $(wait_stack)"
