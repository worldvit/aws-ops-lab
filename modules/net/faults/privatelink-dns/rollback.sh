#!/bin/bash
# net privatelink-dns — rollback
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
need STS_VPCE STS_SG
aws ec2 modify-vpc-endpoint --vpc-endpoint-id "$STS_VPCE" --private-dns-enabled >/dev/null && echo "  엔드포인트 프라이빗 DNS 켬"
aws ec2 authorize-security-group-ingress --group-id "$STS_SG" --protocol tcp --port 443 --cidr 10.20.0.0/16 >/dev/null 2>&1 \
  && echo "  엔드포인트 SG 443 허용 복원" || echo "  엔드포인트 SG 443 규칙 이미 있음"
