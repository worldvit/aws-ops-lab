#!/bin/bash
# net sg-nacl — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: 서비스 서브넷 NACL($SID-net-svc-nacl)과 내부 서비스 보안 그룹($SID-net-svc-sg)만
need NACL SVC_SG
V=$(pick_variant 3)
case $V in
  1) aws ec2 replace-network-acl-entry --network-acl-id "$NACL" --egress --rule-number 100 --protocol tcp \
       --port-range From=1024,To=32767 --cidr-block 10.0.0.0/16 --rule-action allow ;;
  2) aws ec2 create-network-acl-entry --network-acl-id "$NACL" --ingress --rule-number 90 --protocol tcp \
       --port-range From=8080,To=8080 --cidr-block 10.0.10.0/24 --rule-action deny ;;
  3) aws ec2 revoke-security-group-ingress --group-id "$SVC_SG" --protocol tcp --port 8080 --cidr 10.0.0.0/16 >/dev/null &&
     aws ec2 authorize-security-group-ingress --group-id "$SVC_SG" --protocol tcp --port 8080 --cidr 10.0.0.0/24 >/dev/null ;;
esac || exit 1
record $V
