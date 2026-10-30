#!/bin/bash
# cmp 모듈 정리 훅 — 수강생이 CLI로 직접 만든 cmp 리소스를 지운다(ASG → ALB → TG → LT → SG).
# common/cleanup.sh 가 스택을 지우기 전에 호출한다. 환경 층(L2)이 만든 것이면 건너뛴다(스택 삭제가 처리).
set -uo pipefail
: "${SID:?}"
read -r A_NAME A_STACK <<<"$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$SID-cmp-asg" \
  --query 'AutoScalingGroups[0].[AutoScalingGroupName,Tags[?Key==`aws:cloudformation:stack-name`]|[0].Value]' --output text 2>/dev/null)"
if [ "${A_NAME:-None}" != None ] && [ "${A_STACK:-None}" = None ]; then
  aws autoscaling delete-auto-scaling-group --auto-scaling-group-name "$SID-cmp-asg" --force-delete && echo "  ASG 삭제 요청"
  while aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$SID-cmp-asg" --query 'AutoScalingGroups[0].AutoScalingGroupName' --output text | grep -q "$SID"; do sleep 15; done
fi
cfn_managed() { aws resourcegroupstaggingapi get-resources --resource-arn-list "$1" --query 'ResourceTagMappingList[0].Tags[?Key==`aws:cloudformation:stack-name`]|[0].Value' --output text 2>/dev/null | grep -qv None; }
ALB=$(aws elbv2 describe-load-balancers --names "$SID-cmp-alb" --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null)
if [ -n "$ALB" ] && [ "$ALB" != None ] && ! cfn_managed "$ALB"; then
  aws elbv2 delete-load-balancer --load-balancer-arn "$ALB" && aws elbv2 wait load-balancers-deleted --load-balancer-arns "$ALB" && echo "  ALB 삭제"
fi
TG=$(aws elbv2 describe-target-groups --names "$SID-cmp-tg" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null)
if [ -n "$TG" ] && [ "$TG" != None ] && ! cfn_managed "$TG"; then   # 리스너가 ALB와 함께 사라지는 데 몇 초 걸린다
  for _ in 1 2 3 4 5 6; do aws elbv2 delete-target-group --target-group-arn "$TG" 2>/dev/null && { echo "  TG 삭제"; break; }; sleep 10; done
fi
LT=$(aws ec2 describe-launch-templates --launch-template-names "$SID-cmp-lt" --query 'LaunchTemplates[0].Tags[?Key==`aws:cloudformation:stack-name`]|[0].Value' --output text 2>/dev/null)
[ "$LT" = None ] && ! aws cloudformation describe-stacks --stack-name "$SID-l2" >/dev/null 2>&1 && aws ec2 delete-launch-template --launch-template-name "$SID-cmp-lt" >/dev/null && echo "  LT 삭제"
sleep 20   # 네트워크 인터페이스 해제 대기
for sg in app alb; do
  id=$(aws ec2 describe-security-groups --filters Name=group-name,Values="$SID-cmp-$sg-sg" --query 'SecurityGroups[?!(Tags[?Key==`aws:cloudformation:stack-name`])].GroupId|[0]' --output text 2>/dev/null)
  [ -n "$id" ] && [ "$id" != None ] && aws ec2 delete-security-group --group-id "$id" >/dev/null && echo "  SG 삭제: $sg"
done
