#!/bin/bash
# net 모듈 공통 함수: 리소스(<학번>-net-*, <학번>-base-*) 찾기, Run Command, 경로 점검(probe)
# 장애 스크립트(inject·rollback)는 common/lib.sh 의 SID·LAB 검사를 거친다. probe.sh·verify.sh 는 NET_NO_LAB=1 로 부른다.
if [ -n "${NET_NO_LAB:-}" ]; then
  set -uo pipefail; : "${SID:?SID 환경변수에 학번을 넣으세요. 예) source ~/opslab-env.sh}"
  export AWS_REGION="${AWS_REGION:-ap-northeast-2}"
else
  source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../common/lib.sh"
fi
SVC_IP=10.20.2.10

byname() {  # $1=ec2 describe 명령 $2=Name 태그 $3=JMESPath 필드 — Course=opslab 태그가 붙은 것 중 첫 번째
  aws ec2 "$1" --filters Name=tag:Name,Values="$2" Name=tag:Course,Values=opslab --query "$3" --output text 2>/dev/null | head -1
}
inst() { aws ec2 describe-instances --filters Name=tag:Name,Values="$1" Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null; }

NET_VPC=$(byname describe-vpcs "$SID-net-vpc" 'Vpcs[0].VpcId')
BASE_VPC=$(byname describe-vpcs "$SID-base-vpc" 'Vpcs[0].VpcId')
BASE_APP_RT=$(byname describe-route-tables "$SID-base-app-rt" 'RouteTables[0].RouteTableId')
TGW_RT_SUB=$(byname describe-route-tables "$SID-net-tgw-rt" 'RouteTables[0].RouteTableId')
FW_RT=$(byname describe-route-tables "$SID-net-fw-rt" 'RouteTables[0].RouteTableId')
SVC_RT=$(byname describe-route-tables "$SID-net-svc-rt" 'RouteTables[0].RouteTableId')
SVC_SG=$(byname describe-security-groups "$SID-net-svc-sg" 'SecurityGroups[0].GroupId')
LOADGEN=$(inst "$SID-base-loadgen"); SVC=$(inst "$SID-net-svc")
NAT=$(aws ec2 describe-nat-gateways --filter Name=tag:Name,Values="$SID-base-nat" Name=state,Values=available --query 'NatGateways[0].NatGatewayId' --output text 2>/dev/null)
TGW=$(aws ec2 describe-transit-gateways --filters Name=tag:Name,Values="$SID-net-tgw" Name=state,Values=available,pending,modifying --query 'TransitGateways[0].TransitGatewayId' --output text 2>/dev/null)
TGW_ROUTE_TABLE=$(aws ec2 describe-transit-gateways --transit-gateway-ids "$TGW" --query 'TransitGateways[0].Options.AssociationDefaultRouteTableId' --output text 2>/dev/null)
att() { aws ec2 describe-transit-gateway-vpc-attachments --filters Name=tag:Name,Values="$1" Name=state,Values=available,pending,modifying --query 'TransitGatewayVpcAttachments[0].TransitGatewayAttachmentId' --output text 2>/dev/null; }
ATT_BASE=$(att "$SID-net-tgw-att-base"); ATT_NET=$(att "$SID-net-tgw-att-net")
STS_VPCE=$(aws ec2 describe-vpc-endpoints --filters Name=tag:Name,Values="$SID-net-vpce-sts" Name=vpc-endpoint-state,Values=available,pending,modifying --query 'VpcEndpoints[0].VpcEndpointId' --output text 2>/dev/null)
STS_SG=$(byname describe-security-groups "$SID-net-vpce-sts-sg" 'SecurityGroups[0].GroupId')
NACL=$(byname describe-network-acls "$SID-net-svc-nacl" 'NetworkAcls[0].NetworkAclId')
FW_RULES_ARN=$(aws network-firewall describe-rule-group --rule-group-name "$SID-net-fw-rules" --type STATEFUL --query 'RuleGroupResponse.RuleGroupArn' --output text 2>/dev/null)
FW_POLICY_ARN=$(aws network-firewall describe-firewall-policy --firewall-policy-name "$SID-net-fw-policy" --query 'FirewallPolicyResponse.FirewallPolicyArn' --output text 2>/dev/null)

need() {  # 장애 스크립트가 쓰는 리소스가 다 있는지 확인. 인자: 변수 이름들
  local v; for v in "$@"; do
    case "${!v:-}" in ""|None) echo "net 모듈 리소스($v)를 찾지 못했습니다. 1단계 구축(이름 태그 포함)을 먼저 끝내세요."; exit 3;; esac
  done
}

ssm_run() {  # $1=인스턴스 ID(공백 구분 여러 개 가능) $2=셸 명령 $3=대기 초(기본 60) → 인스턴스별 출력
  local ids=$1 cid i st
  cid=$(aws ssm send-command --instance-ids $ids --document-name AWS-RunShellScript --comment "opslab net" \
        --timeout-seconds 60 --parameters "$(jq -nc --arg c "$2" '{commands:[$c],executionTimeout:["'"${3:-60}"'"]}')" \
        --query Command.CommandId --output text) || return 1
  for i in $(seq 1 $(( ${3:-60} / 2 + 10 ))); do
    st=$(aws ssm list-commands --command-id "$cid" --query 'Commands[0].Status' --output text)
    case "$st" in Success|Failed|TimedOut|Cancelled) break;; esac; sleep 2
  done
  for i in $ids; do
    aws ssm get-command-invocation --command-id "$cid" --instance-id "$i" --query 'StandardOutputContent' --output text 2>/dev/null
  done
}
app_ids() { aws ec2 describe-instances --filters Name=tag:Name,Values="$SID-cmp-app" Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId' --output text; }
alb_dns() { aws elbv2 describe-load-balancers --names "$SID-cmp-alb" --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null; }

# ── 경로 점검: 결과를 "키=값" 줄로 출력한다 (probe.sh 가 표로, verify.sh 가 판정에 사용)
probe_raw() {
  local dns ips lg sv
  dns=$(alb_dns)
  # ① 사용자(CloudShell) → ALB
  local ok=0; for _ in 1 2 3 4 5; do curl -s -o /dev/null -m 5 -w '%{http_code}' "http://$dns/health" | grep -q 200 && ok=$((ok+1)); done
  echo "user_alb=$ok/5"
  # ②·③ loadgen 에서: ALB 공인 IP별(NAT 경유), 내부 서비스(TGW·방화벽 경유)
  lg='dns='"$dns"'; for ip in $(getent ahostsv4 $dns | awk "{print \$1}" | sort -u); do ok=0; for i in 1 2 3 4 5; do c=$(curl -s -o /dev/null -m 4 --connect-timeout 3 -w "%{http_code}" --resolve $dns:80:$ip http://$dns/health); [ "$c" = 200 ] && ok=$((ok+1)); done; echo "nat_alb_$ip=$ok/5"; done
ok=0; last=; for i in 1 2 3 4 5; do c=$(curl -s -o /dev/null -m 4 --connect-timeout 3 -w "%{http_code}" http://'"$SVC_IP"':8080/health); [ "$c" = 200 ] && ok=$((ok+1)); last=$c; done; echo "tgw_svc=$ok/5 last_code=$last"'
  # ④ 내부 서비스 서버에서: STS 이름 해석 결과와 호출(PrivateLink)
  sv='ip=$(getent ahostsv4 sts.'"$AWS_REGION"'.amazonaws.com | awk "{print \$1}" | head -1); echo "sts_dns=${ip:-none}"
if AWS_STS_REGIONAL_ENDPOINTS=regional AWS_MAX_ATTEMPTS=1 timeout 12 aws sts get-caller-identity --region '"$AWS_REGION"' --cli-connect-timeout 4 --cli-read-timeout 4 >/dev/null 2>/tmp/sts.err; then echo sts_call=ok; else echo "sts_call=fail $(tail -c 120 /tmp/sts.err | tr "\n" " ")"; fi'
  [ -n "$LOADGEN" ] && [ "$LOADGEN" != None ] && ssm_run "$LOADGEN" "$lg" 60 &
  [ -n "$SVC" ] && [ "$SVC" != None ] && ssm_run "$SVC" "$sv" 40 &
  wait
}

# ── Network Firewall 도우미
fw_rules_json() {  # $1=허용 포트 $2=허용 출발지 — 상태 저장 규칙 그룹 본문(정상: 8080, 10.0.0.0/16)
  jq -nc --arg p "$1" --arg s "$2" '{RulesSource:{StatefulRules:[
    {Action:"PASS",Header:{Protocol:"TCP",Source:$s,SourcePort:"ANY",Direction:"FORWARD",Destination:"10.20.2.0/24",DestinationPort:$p},
     RuleOptions:[{Keyword:"sid",Settings:["1"]}]},
    {Action:"DROP",Header:{Protocol:"IP",Source:"ANY",SourcePort:"ANY",Direction:"ANY",Destination:"ANY",DestinationPort:"ANY"},
     RuleOptions:[{Keyword:"sid",Settings:["2"]}]}]}}'
}
fw_set_rules() {  # $1=포트 $2=출발지
  local tok; tok=$(aws network-firewall describe-rule-group --rule-group-arn "$FW_RULES_ARN" --query UpdateToken --output text)
  aws network-firewall update-rule-group --rule-group-arn "$FW_RULES_ARN" --update-token "$tok" \
    --rule-group "$(fw_rules_json "$1" "$2")" >/dev/null
}
fw_policy_edit() {  # $1=jq 식 — 방화벽 정책 본문을 고친다
  local out tok body
  out=$(aws network-firewall describe-firewall-policy --firewall-policy-arn "$FW_POLICY_ARN" --output json) || return 1
  tok=$(jq -r .UpdateToken <<<"$out"); body=$(jq -c ".FirewallPolicy | $1" <<<"$out")
  aws network-firewall update-firewall-policy --firewall-policy-arn "$FW_POLICY_ARN" --update-token "$tok" --firewall-policy "$body" >/dev/null
}
