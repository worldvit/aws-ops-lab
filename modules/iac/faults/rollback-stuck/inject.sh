#!/bin/bash
# iac rollback-stuck — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: 외부 의존 설정(SSM /opslab/iac/dependency 또는 버킷의 config/allowed.json), 수동 SG 1개, 스택 업데이트 1회.
# 시나리오: 외부 시스템이 v2 로 먼저 이전(v1 거부) → 릴리스 v2 배포가 다른 이유(SG 이름 충돌)로 실패 → 롤백이 v1 사전 점검에서 거부되어 멈춤
need_stack
[ "$(stack_status)" = UPDATE_ROLLBACK_FAILED ] && exit 1
B=$(sres ArtifactBucket); save prev_promo "$(sparam PromoText)"
[ "$(sparam PromoText)" = v1 ] || { deploy_app PromoText=v1; wait_stack >/dev/null; }   # 출발점을 v1 로
V_=$(pick_variant 2)
case $V_ in
  1) aws ssm put-parameter --name /opslab/iac/dependency --type String --overwrite --value "only:v2" >/dev/null ;;
  2) printf '{"allowed": ["v2"]}' | aws s3 cp - "s3://$B/config/allowed.json" --quiet ;;
esac || exit 1
aws ec2 create-security-group --group-name "$SID-iac-admin-sg-v2" --description "created manually" \
  --vpc-id "$(aws cloudformation list-exports --query "Exports[?Name=='$SID-base-VpcId'].Value" --output text)" >/dev/null 2>&1
deploy_app PromoText=v2 AdminSgName="$SID-iac-admin-sg-v2"
[ "$(wait_stack 1200)" = UPDATE_ROLLBACK_FAILED ] || exit 1
record $V_
