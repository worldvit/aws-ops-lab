#!/bin/bash
# cmp target-unhealthy — rollback. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
aws elbv2 modify-target-group --target-group-arn "$TG_ARN" --health-check-path /health --health-check-port traffic-port >/dev/null && echo "  TG 헬스체크 원복"
aws ec2 authorize-security-group-ingress --group-id "$APP_SG" \
  --ip-permissions "IpProtocol=tcp,FromPort=8080,ToPort=8080,UserIdGroupPairs=[{GroupId=$ALB_SG}]" >/dev/null 2>&1 && echo "  SG 규칙 복원" || echo "  SG 규칙 이미 존재"
aws autoscaling resume-processes --auto-scaling-group-name "$ASG" && echo "  ASG 프로세스 재개"
