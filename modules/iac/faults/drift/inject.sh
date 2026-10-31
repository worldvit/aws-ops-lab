#!/bin/bash
# iac drift — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: 스택 $STACK 이 관리하는 리소스 하나를 API(콘솔과 같은 효과)로 직접 바꾼다. 스택은 건드리지 않는다.
need_stack
V_=$(pick_variant 3)
case $V_ in
  1) aws ec2 authorize-security-group-ingress --group-id "$(sres AdminSg)" --protocol tcp --port 22 --cidr 0.0.0.0/0 >/dev/null ;;
  2) aws s3api put-bucket-versioning --bucket "$(sres ArtifactBucket)" --versioning-configuration Status=Suspended ;;
  3) aws elbv2 modify-rule --rule-arn "$(sres PromoRule)" --actions \
       'Type=fixed-response,FixedResponseConfig={StatusCode=200,ContentType=text/plain,MessageBody="promo SALE 90% (hotfix)"}' >/dev/null ;;
esac || exit 1
record $V_
