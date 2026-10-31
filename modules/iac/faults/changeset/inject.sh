#!/bin/bash
# iac changeset — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: 스택 $STACK 에 변경셋 1개를 만들어 검토 없이 실행(버킷 이름 규칙 변경 → 버킷 교체). 옛 버킷은 Retain 으로 남는다.
need_stack
[ "$(stack_status)" = UPDATE_ROLLBACK_FAILED ] && exit 1
save old_bucket "$(sres ArtifactBucket)"
CS="naming-rule-$(date +%H%M%S)"
P=$(aws cloudformation describe-stacks --stack-name "$STACK" --query 'Stacks[0].Parameters[].ParameterKey' --output text | tr '\t' '\n' | grep -v BucketSuffix | sed 's/.*/ParameterKey=&,UsePreviousValue=true/')
aws cloudformation create-change-set --stack-name "$STACK" --change-set-name "$CS" --use-previous-template --capabilities CAPABILITY_NAMED_IAM \
  --parameters $P ParameterKey=BucketSuffix,ParameterValue=-prod --description "bucket naming rule (by automation)" >/dev/null || exit 1
aws cloudformation wait change-set-create-complete --stack-name "$STACK" --change-set-name "$CS" || exit 1
aws cloudformation execute-change-set --stack-name "$STACK" --change-set-name "$CS" || exit 1
[ "$(wait_stack)" = UPDATE_COMPLETE ] || exit 1
record 1
