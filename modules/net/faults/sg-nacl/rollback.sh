#!/bin/bash
# net sg-nacl — rollback. 수강생이 일부를 고친 상태에서도 정상 상태로 되돌린다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
need NACL SVC_SG
aws ec2 replace-network-acl-entry --network-acl-id "$NACL" --egress --rule-number 100 --protocol tcp \
    --port-range From=1024,To=65535 --cidr-block 10.0.0.0/16 --rule-action allow 2>/dev/null \
  || aws ec2 create-network-acl-entry --network-acl-id "$NACL" --egress --rule-number 100 --protocol tcp \
    --port-range From=1024,To=65535 --cidr-block 10.0.0.0/16 --rule-action allow
echo "  NACL 아웃바운드 100: 10.0.0.0/16 tcp 1024-65535 허용"
aws ec2 delete-network-acl-entry --network-acl-id "$NACL" --ingress --rule-number 90 2>/dev/null && echo "  NACL 인바운드 90 삭제" || true
aws ec2 revoke-security-group-ingress --group-id "$SVC_SG" --protocol tcp --port 8080 --cidr 10.0.0.0/24 >/dev/null 2>&1 && echo "  SG 8080 10.0.0.0/24 규칙 삭제" || true
aws ec2 authorize-security-group-ingress --group-id "$SVC_SG" --protocol tcp --port 8080 --cidr 10.0.0.0/16 >/dev/null 2>&1 \
  && echo "  SG 8080 10.0.0.0/16 허용 복원" || echo "  SG 8080 10.0.0.0/16 규칙 이미 있음"
