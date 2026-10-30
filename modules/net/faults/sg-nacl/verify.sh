#!/bin/bash
# net sg-nacl 판정 — 경로 ③, 서비스 서브넷 NACL(양방향)과 서비스 보안 그룹을 본다. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start sg-nacl
echo "[1] 경로 점검"; chk_tgw
echo "[2] NACL — 상태 비저장이라 요청(인바운드)과 응답(아웃바운드)을 따로 허용해야 한다"
E=$(aws ec2 describe-network-acls --network-acl-ids "$NACL" --query 'NetworkAcls[0].Entries' --output json 2>/dev/null)
first() {  # $1=egress(true/false) $2=포트 — 10.0.10.0/24(loadgen)에 처음 걸리는 규칙의 동작
  jq -r --argjson e "$1" --argjson p "$2" '[.[] | select(.Egress==$e and .RuleNumber<32767)
    | select(.Protocol=="-1" or (.Protocol=="6" and .PortRange.From<=$p and .PortRange.To>=$p))
    | select(.CidrBlock as $c | ["10.0.0.0/16","10.0.10.0/24","0.0.0.0/0"] | index($c))]
    | sort_by(.RuleNumber) | .[0] | if . then "\(.RuleNumber) \(.RuleAction)" else "없음" end' <<<"$E"
}
r=$(first false 8080); [ "${r#* }" = allow ] && ok "인바운드 8080 (loadgen 서브넷): 규칙 $r" || ng "인바운드 8080 (loadgen 서브넷): 규칙 $r"
for p in 32768 45000 60999; do
  r=$(first true $p); [ "${r#* }" = allow ] && ok "아웃바운드 응답 포트 $p: 규칙 $r" || ng "아웃바운드 응답 포트 $p: 규칙 $r"
done
echo "[3] 서비스 보안 그룹"
n=$(aws ec2 describe-security-groups --group-ids "$SVC_SG" --query "length(SecurityGroups[0].IpPermissions[?FromPort<=\`8080\` && ToPort>=\`8080\`].IpRanges[]|[?CidrIp=='10.0.0.0/16'])" --output text)
[ "${n:-0}" -ge 1 ] && ok "SG 8080 출발지 10.0.0.0/16 허용" || ng "SG 8080 출발지에 10.0.0.0/16(기반 VPC) 없음"
finish
