#!/bin/bash
# net tgw-route — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: 기반 VPC 앱 라우팅 테이블, 사내 서비스 VPC 방화벽 라우팅 테이블, TGW 기본 라우팅 테이블의 전파 설정 중 하나
need BASE_APP_RT FW_RT TGW TGW_ROUTE_TABLE ATT_BASE
V=$(pick_variant 3)
case $V in
  1) aws ec2 delete-route --route-table-id "$BASE_APP_RT" --destination-cidr-block 10.20.0.0/16 ;;
  2) aws ec2 delete-route --route-table-id "$FW_RT" --destination-cidr-block 10.0.0.0/16 ;;
  3) aws ec2 disable-transit-gateway-route-table-propagation --transit-gateway-route-table-id "$TGW_ROUTE_TABLE" \
       --transit-gateway-attachment-id "$ATT_BASE" >/dev/null ;;
esac || exit 1
record $V
