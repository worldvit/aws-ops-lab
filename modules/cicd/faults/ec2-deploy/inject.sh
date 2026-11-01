#!/bin/bash
# cicd ec2-deploy — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: 앱 서버 역할(<학번>-base-ec2-role) 또는 배포 역할(<학번>-cicd-deploy-role)의 권한 하나, 새 릴리스 실행 1회.
need_pipe
V_=$(pick_variant 2)
case $V_ in
  1) put_deny "$SID-base-ec2-role" '["s3:GetObject","s3:GetObjectVersion"]' "arn:aws:s3:::$(envout CicdBucket)/*" ;;
  2) aws iam detach-role-policy --role-name "$SID-cicd-deploy-role" --policy-arn arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole ;;
esac || exit 1
sleep 20
E=$(start_release "$(new_ver)" 0) || exit 1; save exec "$E"
[ "$(AUTO_APPROVE=1 wait_exec "$E" 2700)" = Failed ] || exit 1
record $V_
