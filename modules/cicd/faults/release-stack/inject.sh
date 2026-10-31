#!/bin/bash
# cicd release-stack — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: 변경셋을 실행하는 역할(<학번>-cicd-cfn-role) 권한 또는 릴리스 스택(<학번>-cicd-release) 상태, 새 릴리스 실행 1회.
need_pipe
V_=$(pick_variant 2)
save prev_release "$(good_release)"
case $V_ in
  1) put_deny "$SID-cicd-cfn-role" '["ssm:PutParameter"]' ;;
  2) # 릴리스 스택을 지웠다가 첫 생성이 실패한 상태(ROLLBACK_COMPLETE)로 만든다
     aws cloudformation delete-stack --stack-name "$RSTACK" && aws cloudformation wait stack-delete-complete --stack-name "$RSTACK" &&
     put_deny "$SID-cicd-cfn-role" '["ssm:PutParameter"]' && sleep 20 &&
     aws cloudformation create-stack --stack-name "$RSTACK" --template-body file://$D/../../cicd/release.yaml        --parameters ParameterKey=StudentId,ParameterValue=$SID ParameterKey=AppVersion,ParameterValue=$(load prev_release)        --role-arn "$(envout CfnRoleArn)" >/dev/null &&
     { for i in $(seq 1 60); do   # 첫 생성 실패 → ROLLBACK_COMPLETE 까지 (stack-rollback-complete 대기 명령은 이 상태를 기다리지 못함)
         case "$(aws cloudformation describe-stacks --stack-name "$RSTACK" --query 'Stacks[0].StackStatus' --output text)" in *_IN_PROGRESS) sleep 10;; *) break;; esac; done; }
     del_deny "$SID-cicd-cfn-role"
     [ "$(aws cloudformation describe-stacks --stack-name "$RSTACK" --query 'Stacks[0].StackStatus' --output text)" = ROLLBACK_COMPLETE ] ;;
esac || exit 1
sleep 20
E=$(start_release "$(new_ver)" 0) || exit 1; save exec "$E"
[ "$(AUTO_APPROVE=1 wait_exec "$E" 900)" = Failed ] || exit 1
record $V_
