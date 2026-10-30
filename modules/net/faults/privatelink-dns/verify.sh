#!/bin/bash
# net privatelink-dns 판정 — 경로 ④(이름 해석과 호출), 엔드포인트 설정을 본다. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start privatelink-dns
echo "[1] 경로 점검"; chk_sts
echo "[2] 엔드포인트 설정"
read -r PD STATE <<<"$(aws ec2 describe-vpc-endpoints --vpc-endpoint-ids "$STS_VPCE" --query 'VpcEndpoints[0].[PrivateDnsEnabled,State]' --output text 2>/dev/null)"
[ "$PD" = True ] && ok "프라이빗 DNS 켜짐" || ng "프라이빗 DNS: ${PD:-엔드포인트 없음}"
[ "$STATE" = available ] && ok "엔드포인트 상태 available" || ng "엔드포인트 상태 ${STATE:-없음}"
n=$(aws ec2 describe-security-groups --group-ids "$STS_SG" --query 'length(SecurityGroups[0].IpPermissions[?FromPort<=`443` && ToPort>=`443`])' --output text 2>/dev/null)
[ "${n:-0}" -ge 1 ] && ok "엔드포인트 SG: 443 인바운드 허용" || ng "엔드포인트 SG에 443 인바운드 규칙 없음"
finish
