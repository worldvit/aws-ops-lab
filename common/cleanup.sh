#!/bin/bash
# 비용 정리 스크립트 — common/lifecycle.csv(리소스 수명표)를 기준으로 동작한다.
# 실행 위치: CloudShell
#   SID=s01 bash cleanup.sh night     # 매일 실습 종료 시: 야간 처리(중지·0대 축소)
#   SID=s01 bash cleanup.sh morning   # 다음 날 시작 시: 야간 처리 원복
#   SID=s01 bash cleanup.sh status    # 수명표 기준 현재 상태 출력
#   SID=s01 bash cleanup.sh final     # 과정 종료(Day 8): Owner 태그가 붙은 전체 리소스 삭제
set -uo pipefail
: "${SID:?SID 환경변수에 학번을 넣으세요. 예) export SID=s01}"
export AWS_REGION="${AWS_REGION:-ap-northeast-2}"
MODE="${1:-status}"
CSV="$(dirname "$0")/lifecycle.csv"

ec2_id() { aws ec2 describe-instances --filters Name=tag:Name,Values="$1" Name=tag:Owner,Values="$SID" \
  Name=instance-state-name,Values=pending,running,stopping,stopped --query 'Reservations[].Instances[].InstanceId' --output text; }

handle() {  # kind name action
  local kind=$1 name=$2 act=$3
  case "$kind:$act" in
    ec2:stop)  id=$(ec2_id "$name"); [ -n "$id" ] && aws ec2 stop-instances --instance-ids $id >/dev/null && echo "  중지: $name ($id)";;
    ec2:start) id=$(ec2_id "$name"); [ -n "$id" ] && aws ec2 start-instances --instance-ids $id >/dev/null && echo "  시작: $name ($id)";;
    asg:scale0)
      aws autoscaling update-auto-scaling-group --auto-scaling-group-name "$name" --min-size 0 --desired-capacity 0 2>/dev/null \
        && echo "  0대 축소: $name";;
    asg:min=*)
      IFS=';' read -r a b c <<<"$act"
      aws autoscaling update-auto-scaling-group --auto-scaling-group-name "$name" \
        --min-size "${a#min=}" --max-size "${b#max=}" --desired-capacity "${c#desired=}" 2>/dev/null \
        && echo "  복원: $name (${act})";;
    *:keep|*:-) : ;;
    *) echo "  (알 수 없는 처리: $kind $act)";;
  esac
}

status() {
  echo "== $SID 리소스 상태 =="
  aws resourcegroupstaggingapi get-resources --tag-filters Key=Owner,Values="$SID" Key=Course,Values=skons-ops \
    --query 'ResourceTagMappingList[].ResourceARN' --output text | tr '\t' '\n' | sed 's/^/  /'
  echo "-- Auto Scaling 그룹 --"
  aws autoscaling describe-auto-scaling-groups --filters Name=tag:Owner,Values="$SID" \
    --query 'AutoScalingGroups[].[AutoScalingGroupName,MinSize,DesiredCapacity,MaxSize]' --output text | sed 's/^/  /'
  echo "-- 시간당 과금 리소스 --"
  aws ec2 describe-nat-gateways --filter Name=tag:Owner,Values="$SID" Name=state,Values=available \
    --query 'NatGateways[].[NatGatewayId,Tags[?Key==`Name`]|[0].Value]' --output text | sed 's/^/  NAT /'
  aws ec2 describe-instances --filters Name=tag:Owner,Values="$SID" Name=instance-state-name,Values=running \
    --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`]|[0].Value,InstanceType]' --output text | sed 's/^/  EC2 /'
}

case "$MODE" in
  night|morning)
    echo "== $(date '+%F %T') $SID $MODE 처리 =="
    col=5; [ "$MODE" = morning ] && col=6
    grep -v '^#' "$CSV" | while IFS=, read -r kind name _c _u night morning _note; do
      name=${name//<SID>/$SID}
      act=$night; [ "$MODE" = morning ] && act=$morning
      handle "$kind" "$name" "$act"
    done
    status;;
  status) status;;
  final)
    echo "== $SID 전체 리소스 삭제 (Day 8 종료 시에만) =="
    read -r -p "정말 삭제하려면 학번($SID)을 다시 입력하세요: " ans; [ "$ans" = "$SID" ] || exit 1
    # 1) 따라잡기(catchup) 스택 먼저 삭제
    for st in $(aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE ROLLBACK_COMPLETE \
                 --query "StackSummaries[?starts_with(StackName,'$SID-') && contains(StackName,'catchup')].StackName" --output text); do
      echo "  스택 삭제: $st"; aws cloudformation delete-stack --stack-name "$st"; aws cloudformation wait stack-delete-complete --stack-name "$st"
    done
    # 2) CLI로 직접 만든 리소스 (ASG → ALB → TG → LT → SG 순서)
    if aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$SID-d1-asg" --query 'AutoScalingGroups[0]' --output text | grep -q .; then
      aws autoscaling delete-auto-scaling-group --auto-scaling-group-name "$SID-d1-asg" --force-delete 2>/dev/null && echo "  ASG 삭제 요청"
      while aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$SID-d1-asg" --query 'AutoScalingGroups[0].AutoScalingGroupName' --output text | grep -q "$SID"; do sleep 15; done
    fi
    ALB=$(aws elbv2 describe-load-balancers --names "$SID-d1-alb" --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null)
    if [ -n "$ALB" ] && [ "$ALB" != None ]; then
      aws elbv2 delete-load-balancer --load-balancer-arn "$ALB" && aws elbv2 wait load-balancers-deleted --load-balancer-arns "$ALB" && echo "  ALB 삭제"
    fi
    TG=$(aws elbv2 describe-target-groups --names "$SID-d1-tg" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null)
    [ -n "$TG" ] && [ "$TG" != None ] && aws elbv2 delete-target-group --target-group-arn "$TG" && echo "  TG 삭제"
    aws ec2 delete-launch-template --launch-template-name "$SID-d1-lt" >/dev/null 2>&1 && echo "  LT 삭제"
    sleep 30   # ENI 해제 대기
    for sg in app alb; do
      id=$(aws ec2 describe-security-groups --filters Name=group-name,Values="$SID-d1-$sg-sg" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
      [ -n "$id" ] && [ "$id" != None ] && aws ec2 delete-security-group --group-id "$id" && echo "  SG 삭제: $sg"
    done
    # 3) 나머지 스택 (기반 스택은 마지막)
    for st in $(aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE ROLLBACK_COMPLETE \
                 --query "StackSummaries[?starts_with(StackName,'$SID-')].StackName" --output text | tr '\t' '\n' | sort -r); do
      echo "  스택 삭제: $st"; aws cloudformation delete-stack --stack-name "$st"; aws cloudformation wait stack-delete-complete --stack-name "$st"
    done
    status;;
  *) sed -n '2,8p' "$0"; exit 1;;
esac
