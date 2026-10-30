#!/bin/bash
# cmp asg-no-scale — rollback. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
PREV=$(load prev-lt)
aws autoscaling update-auto-scaling-group --auto-scaling-group-name "$ASG" --min-size 2 --max-size 4 \
  --launch-template "LaunchTemplateId=$LT_ID,Version=${PREV:-1}" && echo "  용량 2~4, LT 버전 ${PREV:-1} 원복"
aws autoscaling resume-processes --auto-scaling-group-name "$ASG" && echo "  ASG 프로세스 재개"
POL=$(load prev-policy)
if [ -n "$POL" ]; then
  aws autoscaling put-scaling-policy --auto-scaling-group-name "$ASG" --policy-name "$(echo "$POL" | jq -r .PolicyName)" \
    --policy-type TargetTrackingScaling --target-tracking-configuration "$(echo "$POL" | jq -c .TargetTrackingConfiguration)" >/dev/null \
    && echo "  대상 추적 목표값 원복"
fi
