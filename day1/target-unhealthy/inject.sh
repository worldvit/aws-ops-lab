#!/bin/bash
# Day 1 target-unhealthy — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../common/lib.sh"
# 영향 범위: $SID-d1-tg 헬스체크 설정, $SID-d1-app-sg 인바운드 규칙만 변경
V=$(pick_variant 3)
case $V in
  1) aws elbv2 modify-target-group --target-group-arn "$TG_ARN" --health-check-path /healthz >/dev/null ;;
  2) aws ec2 revoke-security-group-ingress --group-id "$APP_SG" \
       --ip-permissions "IpProtocol=tcp,FromPort=8080,ToPort=8080,UserIdGroupPairs=[{GroupId=$ALB_SG}]" >/dev/null ;;
  3) aws elbv2 modify-target-group --target-group-arn "$TG_ARN" --health-check-port 8081 >/dev/null ;;
esac
record $V
