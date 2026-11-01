#!/bin/bash
# auto failover — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: v1 Route 53 헬스 체크의 확인 경로, v2 주 레코드의 헬스 체크 연결 + ALB 리스너(:80)의 기본 동작(503 응답). 앱 서버는 건드리지 않는다.
H_=$(hc_id); [ -n "$H_" ] && [ "$H_" != None ] || exit 3
save hc "$H_"
V_=$(pick_variant 2)
case $V_ in
  1) # 표준 경로라며 헬스 체크 경로를 /healthz 로 바꿈(앱에는 없는 경로) → 멀쩡한 주 서비스를 비정상으로 판정
     aws route53 update-health-check --health-check-id "$H_" --resource-path /healthz >/dev/null || exit 1 ;;
  2) # 레코드를 다시 만들면서 헬스 체크 연결을 빠뜨림 + 같은 시각 주 서비스(ALB)가 503 을 돌려주기 시작
     aws route53 change-resource-record-sets --hosted-zone-id "$(zone_id)" --change-batch "$(primary_rr)" >/dev/null || exit 1
     aws elbv2 modify-listener --listener-arn "$(listener_arn)"        --default-actions 'Type=fixed-response,FixedResponseConfig={StatusCode=503,ContentType=text/plain,MessageBody=service unavailable}' >/dev/null || exit 1 ;;
esac
record $V_
