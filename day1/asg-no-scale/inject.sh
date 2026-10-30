#!/bin/bash
# Day 1 asg-no-scale — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../common/lib.sh"
# 영향 범위: $SID-d1-asg 용량·프로세스, $SID-d1-lt 새 버전
V=$(pick_variant 3)
save prev-lt "$(asg_lt_version)"
case $V in
  1) aws autoscaling update-auto-scaling-group --auto-scaling-group-name "$ASG" --max-size 2 ;;
  2) aws autoscaling suspend-processes --auto-scaling-group-name "$ASG" --scaling-processes Launch ;;
  3) POL=$(aws autoscaling describe-policies --auto-scaling-group-name "$ASG" --policy-types TargetTrackingScaling --query 'ScalingPolicies[0]' --output json)
     save prev-policy "$POL"
     CFG=$(echo "$POL" | jq -c '.TargetTrackingConfiguration | .TargetValue=100000')
     aws autoscaling put-scaling-policy --auto-scaling-group-name "$ASG" --policy-name "$(echo "$POL" | jq -r .PolicyName)" \
       --policy-type TargetTrackingScaling --target-tracking-configuration "$CFG" >/dev/null ;;
esac
record $V
