#!/bin/bash
# cicd release-stack — rollback. 변경셋 실행 역할의 거부 정책을 지우고, 생성 실패로 남은 릴리스 스택은 지운 뒤 실패한 단계를 다시 돌린다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
need_pipe
del_deny "$SID-cicd-cfn-role"; echo "  변경셋 실행 역할 거부 정책 삭제"
S=$(aws cloudformation describe-stacks --stack-name "$RSTACK" --query 'Stacks[0].StackStatus' --output text 2>/dev/null)
if [ "$S" = UPDATE_ROLLBACK_FAILED ]; then   # 거부 정책 때문에 롤백(이전 값 복원)마저 실패한 상태 — 권한을 되돌린 뒤 롤백을 이어서 끝낸다
  sleep 20; aws cloudformation continue-update-rollback --stack-name "$RSTACK" --role-arn "$(envout CfnRoleArn)" &&
  aws cloudformation wait stack-rollback-complete --stack-name "$RSTACK" && echo "  릴리스 스택 롤백 교착 해소(continue-update-rollback)"
fi
if [ "$S" = ROLLBACK_COMPLETE ]; then
  aws cloudformation delete-stack --stack-name "$RSTACK" && aws cloudformation wait stack-delete-complete --stack-name "$RSTACK" && echo "  ROLLBACK_COMPLETE 릴리스 스택 삭제"
fi
sleep 30
E=$(load exec); r=$(retry_exec "$E"); echo "  실행 ${E:0:8} 다시 실행: $r"
[ "$r" = Succeeded ] || { r=$(redeploy_good "$(load prev_release)"); echo "  정상 릴리스 재배포: $r"; }
