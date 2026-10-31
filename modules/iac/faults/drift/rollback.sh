#!/bin/bash
# iac drift — rollback. 세 가지 변경을 모두 템플릿 값으로 되돌린다(이미 고친 것은 건너뜀).
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
need_stack
aws ec2 revoke-security-group-ingress --group-id "$(sres AdminSg)" --protocol tcp --port 22 --cidr 0.0.0.0/0 >/dev/null 2>&1 && echo "  SG 22 규칙 제거"
aws s3api put-bucket-versioning --bucket "$(sres ArtifactBucket)" --versioning-configuration Status=Enabled && echo "  버킷 버전 관리 Enabled"
aws elbv2 modify-rule --rule-arn "$(sres PromoRule)" --actions \
  "Type=fixed-response,FixedResponseConfig={StatusCode=200,ContentType=text/plain,MessageBody=\"promo $(sparam PromoText)\"}" >/dev/null && echo "  /promo 응답 원복"
