#!/bin/bash
# net tgw-route 판정 — 경로 ③과, 경로 위 라우팅 세 곳(출발 VPC · TGW · 돌아오는 VPC)을 본다. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start tgw-route
echo "[1] 경로 점검"; chk_tgw
echo "[2] 라우팅"
st() { aws ec2 describe-route-tables --route-table-ids "$1" --query "RouteTables[0].Routes[?DestinationCidrBlock=='$2'].[TransitGatewayId,State]|[0]" --output text 2>/dev/null; }
r=$(st "$BASE_APP_RT" 10.20.0.0/16); [ "$r" = "$TGW"$'	'"active" ] && ok "기반 VPC 앱 라우팅 10.20.0.0/16 → TGW" || ng "기반 VPC 앱 라우팅 10.20.0.0/16: ${r:-없음}"
r=$(st "$FW_RT" 10.0.0.0/16);       [ "$r" = "$TGW"$'	'"active" ] && ok "방화벽 서브넷 라우팅 10.0.0.0/16 → TGW" || ng "방화벽 서브넷 라우팅 10.0.0.0/16: ${r:-없음}"
for c in 10.0.0.0/16 10.20.0.0/16; do
  r=$(aws ec2 search-transit-gateway-routes --transit-gateway-route-table-id "$TGW_ROUTE_TABLE" \
      --filters Name=route-search.exact-match,Values=$c Name=state,Values=active --query 'Routes[0].State' --output text 2>/dev/null)
  [ "$r" = active ] && ok "TGW 라우팅 테이블 $c active" || ng "TGW 라우팅 테이블에 $c 경로 없음"
done
finish
