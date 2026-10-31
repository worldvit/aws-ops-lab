#!/bin/bash
# cicd ec2-deploy — rollback. 권한을 정상으로 되돌리고 실패한 배포 단계를 다시 돌린다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
need_pipe
del_deny "$SID-base-ec2-role"
aws iam attach-role-policy --role-name "$SID-cicd-deploy-role" --policy-arn arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole && echo "  배포 역할 AWSCodeDeployRole 연결"
sleep 30
E=$(load exec); r=$(retry_exec "$E"); echo "  실행 ${E:0:8} 다시 실행: $r"
[ "$r" = Succeeded ] || { r=$(redeploy_good); echo "  정상 릴리스 재배포: $r"; }
