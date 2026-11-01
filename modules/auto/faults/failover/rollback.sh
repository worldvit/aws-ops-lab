#!/bin/bash
# auto failover — rollback. 헬스 체크 경로 /health, ALB 리스너를 타깃 그룹으로 전달, 주 레코드에 헬스 체크 연결.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
aws elbv2 modify-listener --listener-arn "$(listener_arn)" --default-actions Type=forward,TargetGroupArn="$(tg_arn)" >/dev/null && echo "  리스너 → $SID-cmp-tg"
H_=$(hc_id)
aws route53 update-health-check --health-check-id "$H_" --resource-path /health --no-inverted --no-disabled >/dev/null && echo "  헬스 체크 $H_ 경로 /health"
aws route53 change-resource-record-sets --hosted-zone-id "$(zone_id)" --change-batch "$(primary_rr "$H_")" >/dev/null && echo "  주 레코드에 헬스 체크 연결"
exit 0
