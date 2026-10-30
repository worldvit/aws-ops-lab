#!/bin/bash
# 비용 정리 스크립트 — Day별 독립 실습: 매일 끝에 Day 0 스택을 뺀 그날의 리소스를 모두 지운다.
# 실행 위치: CloudShell
#   bash ~/opslab/common/cleanup.sh          # 매일 마지막: Day 0 스택을 뺀 전부 삭제 (확인 질문 있음)
#   bash ~/opslab/common/cleanup.sh status   # 남아 있는 실습 리소스와 시간당 과금 리소스 보기
#   bash ~/opslab/common/cleanup.sh final    # Day 8 마지막: 위 삭제 + 장애 주입 기록(SSM) 삭제
# Day 0 스택(<학번>-d0-student)과 그 리소스는 지우지 않는다(과금 없음).
set -uo pipefail
: "${SID:?SID 환경변수에 학번을 넣으세요. 예) source ~/opslab-env.sh}"
export AWS_REGION="${AWS_REGION:-ap-northeast-2}"
MODE="${1:-day}"

status() {
  echo "== $SID 남은 실습 리소스 (Day 0 스택 제외) =="
  echo "-- 스택 --"
  aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE ROLLBACK_COMPLETE DELETE_FAILED \
    --query "StackSummaries[?starts_with(StackName,'$SID-')].[StackName,StackStatus]" --output text | sed 's/^/  /'
  echo "-- 시간당 과금 리소스 --"
  aws ec2 describe-nat-gateways --filter Name=tag:Owner,Values="$SID" Name=state,Values=available,pending \
    --query 'NatGateways[].[NatGatewayId,Tags[?Key==`Name`]|[0].Value]' --output text | sed 's/^/  NAT /'
  aws ec2 describe-instances --filters Name=tag:Owner,Values="$SID" Name=instance-state-name,Values=pending,running,stopping,stopped \
    --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`]|[0].Value,State.Name]' --output text | sed 's/^/  EC2 /'
  aws elbv2 describe-load-balancers --query "LoadBalancers[?starts_with(LoadBalancerName,'$SID-')].LoadBalancerName" --output text | tr '\t' '\n' | sed '/^$/d;s/^/  ALB /'
  aws elbv2 describe-target-groups --query "TargetGroups[?starts_with(TargetGroupName,'$SID-')].TargetGroupName" --output text | tr '\t' '\n' | sed '/^$/d;s/^/  TG  /'
  aws autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[?starts_with(AutoScalingGroupName,'$SID-')].AutoScalingGroupName" --output text | tr '\t' '\n' | sed '/^$/d;s/^/  ASG /'
}

delete_all() {
  read -r -p "Day 0 스택을 뺀 $SID 의 실습 리소스를 모두 삭제합니다. 학번($SID)을 입력하세요: " ans; [ "$ans" = "$SID" ] || exit 1
  # 1) CLI로 직접 만든 리소스 (Day 1: ASG → ALB → TG → LT → SG). 시작 템플릿이 만든 것이면 건너뛴다.
  read -r A_NAME A_STACK <<<"$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$SID-d1-asg" \
    --query 'AutoScalingGroups[0].[AutoScalingGroupName,Tags[?Key==`aws:cloudformation:stack-name`]|[0].Value]' --output text 2>/dev/null)"
  if [ "${A_NAME:-None}" != None ] && [ "${A_STACK:-None}" = None ]; then
    aws autoscaling delete-auto-scaling-group --auto-scaling-group-name "$SID-d1-asg" --force-delete && echo "  ASG 삭제 요청"
    while aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$SID-d1-asg" --query 'AutoScalingGroups[0].AutoScalingGroupName' --output text | grep -q "$SID"; do sleep 15; done
  fi
  cfn_managed() { aws resourcegroupstaggingapi get-resources --resource-arn-list "$1" --query 'ResourceTagMappingList[0].Tags[?Key==`aws:cloudformation:stack-name`]|[0].Value' --output text 2>/dev/null | grep -qv None; }
  ALB=$(aws elbv2 describe-load-balancers --names "$SID-d1-alb" --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null)
  if [ -n "$ALB" ] && [ "$ALB" != None ] && ! cfn_managed "$ALB"; then
    aws elbv2 delete-load-balancer --load-balancer-arn "$ALB" && aws elbv2 wait load-balancers-deleted --load-balancer-arns "$ALB" && echo "  ALB 삭제"
  fi
  TG=$(aws elbv2 describe-target-groups --names "$SID-d1-tg" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null)
  if [ -n "$TG" ] && [ "$TG" != None ] && ! cfn_managed "$TG"; then   # 리스너가 ALB와 함께 사라지는 데 몇 초 걸린다
    for _ in 1 2 3 4 5 6; do aws elbv2 delete-target-group --target-group-arn "$TG" 2>/dev/null && { echo "  TG 삭제"; break; }; sleep 10; done
  fi
  LT=$(aws ec2 describe-launch-templates --launch-template-names "$SID-d1-lt" --query 'LaunchTemplates[0].Tags[?Key==`aws:cloudformation:stack-name`]|[0].Value' --output text 2>/dev/null)
  [ "$LT" = None ] && aws ec2 delete-launch-template --launch-template-name "$SID-d1-lt" >/dev/null && echo "  LT 삭제"
  sleep 20   # 네트워크 인터페이스 해제 대기
  for sg in app alb; do
    id=$(aws ec2 describe-security-groups --filters Name=group-name,Values="$SID-d1-$sg-sg" --query 'SecurityGroups[?!(Tags[?Key==`aws:cloudformation:stack-name`])].GroupId|[0]' --output text 2>/dev/null)
    [ -n "$id" ] && [ "$id" != None ] && aws ec2 delete-security-group --group-id "$id" >/dev/null && echo "  SG 삭제: $sg"
  done
  # 2) 수강생이 만든 CloudWatch 알람 (<학번>-d*)
  AL=$(aws cloudwatch describe-alarms --alarm-name-prefix "$SID-d" --query 'MetricAlarms[].AlarmName' --output text)
  [ -n "$AL" ] && aws cloudwatch delete-alarms --alarm-names $AL && echo "  알람 삭제: $AL"
  # 3) 스택 (Day 0 제외, 늦게 만든 것부터)
  for st in $(aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE ROLLBACK_COMPLETE DELETE_FAILED \
               --query "reverse(sort_by(StackSummaries[?starts_with(StackName,'$SID-') && !contains(StackName,'-d0-')],&CreationTime))[].StackName" --output text); do
    echo "  스택 삭제: $st"; aws cloudformation delete-stack --stack-name "$st"; aws cloudformation wait stack-delete-complete --stack-name "$st" || echo "  ⚠️ $st 삭제 실패 — 콘솔에서 이벤트 확인"
  done
}

case "$MODE" in
  status) status ;;
  day)    delete_all; status ;;
  final)
    delete_all
    N=$(aws ssm get-parameters-by-path --path /opslab/injections --recursive --query 'Parameters[].Name' --output text)
    [ -n "$N" ] && echo $N | xargs -n 10 aws ssm delete-parameters --names >/dev/null && echo "  장애 주입 기록 삭제"
    status ;;
  *) sed -n '2,7p' "$0"; exit 1 ;;
esac
