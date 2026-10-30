#!/bin/bash
# net privatelink-dns — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: STS 인터페이스 엔드포인트($SID-net-vpce-sts)와 그 보안 그룹만
need STS_VPCE STS_SG
V=$(pick_variant 2)
case $V in
  1) aws ec2 modify-vpc-endpoint --vpc-endpoint-id "$STS_VPCE" --no-private-dns-enabled >/dev/null ;;
  2) aws ec2 revoke-security-group-ingress --group-id "$STS_SG" --protocol tcp --port 443 --cidr 10.20.0.0/16 >/dev/null ;;
esac || exit 1
record $V
