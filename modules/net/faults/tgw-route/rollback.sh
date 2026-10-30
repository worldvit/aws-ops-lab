#!/bin/bash
# net tgw-route — rollback. 수강생이 일부를 고친 상태에서도 정상 상태로 되돌린다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
need BASE_APP_RT FW_RT TGW TGW_ROUTE_TABLE ATT_BASE
route() {  # $1=라우팅 테이블 $2=대상 CIDR — TGW로 가는 경로를 만들거나 바꾼다
  aws ec2 create-route --route-table-id "$1" --destination-cidr-block "$2" --transit-gateway-id "$TGW" >/dev/null 2>&1 \
    || aws ec2 replace-route --route-table-id "$1" --destination-cidr-block "$2" --transit-gateway-id "$TGW" >/dev/null
}
route "$BASE_APP_RT" 10.20.0.0/16 && echo "  기반 VPC 앱 라우팅: 10.20.0.0/16 → TGW"
route "$FW_RT" 10.0.0.0/16 && echo "  방화벽 서브넷 라우팅: 10.0.0.0/16 → TGW"
aws ec2 enable-transit-gateway-route-table-propagation --transit-gateway-route-table-id "$TGW_ROUTE_TABLE" \
  --transit-gateway-attachment-id "$ATT_BASE" >/dev/null 2>&1 && echo "  TGW 전파 다시 켬" || echo "  TGW 전파 이미 켜져 있음"
