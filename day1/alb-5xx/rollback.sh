#!/bin/bash
# Day 1 alb-5xx — rollback. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../common/lib.sh"
aws elbv2 modify-load-balancer-attributes --load-balancer-arn "$ALB_ARN" --attributes Key=idle_timeout.timeout_seconds,Value=60 >/dev/null && echo "  유휴 제한 60초"
aws autoscaling update-auto-scaling-group --auto-scaling-group-name "$ASG" --health-check-type ELB --health-check-grace-period 180 && echo "  ASG 헬스체크 ELB"
run_on_app "sed -i 's/^APP_ERROR_RATE=.*/APP_ERROR_RATE=0/' /etc/app/app.env && systemctl restart app"
aws autoscaling resume-processes --auto-scaling-group-name "$ASG" && echo "  ASG 프로세스 재개"
