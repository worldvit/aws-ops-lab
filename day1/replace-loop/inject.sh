#!/bin/bash
# Day 1 replace-loop — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../common/lib.sh"
# 영향 범위: $SID-d1-lt 새 버전 생성, $SID-d1-asg 설정·인스턴스 새로 고침
V=$(pick_variant 3)
# 설정을 바꾸기 전에, 이전 인스턴스 새로 고침이 아직 취소 중이면 끝날 때까지 기다린다(최대 3분).
for _ in $(seq 36); do
  busy=$(aws autoscaling describe-instance-refreshes --auto-scaling-group-name "$ASG" \
    --query 'length(InstanceRefreshes[?Status==`InProgress`||Status==`Pending`||Status==`Cancelling`])' --output text)
  [ "$busy" = 0 ] && break; sleep 5
done
save prev-lt "$(asg_lt_version)"
save prev-grace "$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" --query 'AutoScalingGroups[0].HealthCheckGracePeriod' --output text)"
BASE='curl -fsSL https://raw.githubusercontent.com/worldvit/aws-ops-lab/main/app/install.sh'
case $V in
  1) NEW=$(new_lt_version "$(printf '#!/bin/bash\n%s | bash\nsed -i s/app:app/application:app/ /etc/systemd/system/app.service\nsystemctl daemon-reload\nsystemctl restart app\n' "$BASE")" "gunicorn tuning")
     aws autoscaling update-auto-scaling-group --auto-scaling-group-name "$ASG" --launch-template "LaunchTemplateId=$LT_ID,Version=$NEW" ;;
  2) aws autoscaling update-auto-scaling-group --auto-scaling-group-name "$ASG" --health-check-grace-period 10 ;;
  3) NEW=$(new_lt_version "$(printf '#!/bin/bash\n%s | APP_PORT=8081 bash\n' "$BASE")" "port standardization")
     aws autoscaling update-auto-scaling-group --auto-scaling-group-name "$ASG" --launch-template "LaunchTemplateId=$LT_ID,Version=$NEW" ;;
esac
# 모든 변형: 인스턴스를 새로 띄우게 만들어 교체가 시작되도록 한다.
aws autoscaling start-instance-refresh --auto-scaling-group-name "$ASG" \
  --preferences '{"MinHealthyPercentage":50,"InstanceWarmup":60}' --query InstanceRefreshId --output text >/dev/null || exit 1
record $V
