#!/bin/bash
# Day 1 alb-5xx — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../common/lib.sh"
# 영향 범위: $SID-d1-alb 속성, $SID-d1-asg 헬스체크 유형, 앱 인스턴스의 app 서비스·/etc/app/app.env
V=$(pick_variant 3)
case $V in
  1) aws autoscaling update-auto-scaling-group --auto-scaling-group-name "$ASG" --health-check-type EC2
     run_on_app "systemctl stop app" ;;                                   # 502
  2) aws elbv2 modify-load-balancer-attributes --load-balancer-arn "$ALB_ARN" \
       --attributes Key=idle_timeout.timeout_seconds,Value=1 >/dev/null ;;  # 504
  3) run_on_app "sed -i 's/^APP_ERROR_RATE=.*/APP_ERROR_RATE=0.3/' /etc/app/app.env && systemctl restart app" ;;  # 타깃 500
esac
record $V
