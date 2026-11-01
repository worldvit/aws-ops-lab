#!/bin/bash
# net 모듈 정리 훅 — 수강생이 CLI로 직접 만든 net 리소스를 지운다. common/cleanup.sh 가 스택을 지우기 전에 호출한다.
# 순서: Network Firewall(정책·규칙 그룹) → TGW 연결 → TGW → STS 엔드포인트·SG → NACL → Flow Logs → 로그 그룹
# CloudFormation(<학번>-net-done)이 만든 것은 건너뛴다(스택 삭제가 처리). 단, 장애 주입으로 생긴 규칙 그룹은 여기서 뗀다.
set -uo pipefail
: "${SID:?}"; export AWS_REGION="${AWS_REGION:-ap-northeast-2}"
CFN='aws:cloudformation:stack-name'
nf() { aws network-firewall "$@" 2>/dev/null; }
VPC=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values="$SID-net-vpc" --query 'Vpcs[0].VpcId' --output text 2>/dev/null)
BASE=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values="$SID-base-vpc" --query 'Vpcs[0].VpcId' --output text 2>/dev/null)

# 1) 장애 주입(net-5 변형 3)으로 생긴 무상태 규칙 그룹: 정책에서 떼고 지운다
POL=$(nf describe-firewall-policy --firewall-policy-name "$SID-net-fw-policy" --output json)
if [ -n "$POL" ] && [ "$(jq '.FirewallPolicy.StatelessRuleGroupReferences // [] | length' <<<"$POL")" -gt 0 ]; then
  nf update-firewall-policy --firewall-policy-arn "$(jq -r .FirewallPolicyResponse.FirewallPolicyArn <<<"$POL")" \
    --update-token "$(jq -r .UpdateToken <<<"$POL")" --firewall-policy "$(jq -c '.FirewallPolicy | del(.StatelessRuleGroupReferences)' <<<"$POL")" >/dev/null \
    && echo "  방화벽 정책에서 무상태 규칙 그룹 분리"
fi

# 2) 수강생이 만든 방화벽 → 정책 → 규칙 그룹 (완료 상태 스택이 있으면 스택 삭제가 처리)
if aws cloudformation describe-stacks --stack-name "$SID-net-done" >/dev/null 2>&1; then
  for _ in $(seq 1 12); do   # 장애 주입으로 생긴 규칙 그룹만 지운다
    nf describe-rule-group --rule-group-name "$SID-net-fw-maint" --type STATELESS >/dev/null || break
    nf delete-rule-group --rule-group-name "$SID-net-fw-maint" --type STATELESS >/dev/null && { echo "  규칙 그룹 삭제: $SID-net-fw-maint"; break; }; sleep 10
  done
  echo "  net 완료 상태 스택($SID-net-done)이 있어 나머지는 스택 삭제로 정리"; exit 0
fi
if nf describe-firewall --firewall-name "$SID-net-fw" >/dev/null; then
  # 로그 설정이 있으면 방화벽을 지울 수 없다 → 로그 대상을 하나씩 뺀다(한 번에 하나만 바꿀 수 있음)
  for _ in 1 2 3; do
    LC=$(nf describe-logging-configuration --firewall-name "$SID-net-fw" --query 'LoggingConfiguration.LogDestinationConfigs' --output json)
    [ -z "$LC" ] || [ "$LC" = null ] || [ "$LC" = "[]" ] && break
    nf update-logging-configuration --firewall-name "$SID-net-fw" \
      --logging-configuration "{\"LogDestinationConfigs\":$(jq -c '.[:-1]' <<<"$LC")}" >/dev/null && echo "  방화벽 로그 설정 1개 해제"
  done
  # 방화벽 엔드포인트를 가리키는 라우팅이 남아 있으면 방화벽을 지울 수 없다 → 그 라우팅부터 뺀다
  for ep in $(nf describe-firewall --firewall-name "$SID-net-fw" --query 'FirewallStatus.SyncStates.*.Attachment | [].EndpointId' --output text); do
    for rt in $(aws ec2 describe-route-tables --filters Name=vpc-id,Values="$VPC" --query 'RouteTables[].RouteTableId' --output text); do
      for c in $(aws ec2 describe-route-tables --route-table-ids "$rt" --query "RouteTables[0].Routes[?VpcEndpointId=='$ep'].DestinationCidrBlock" --output text); do
        aws ec2 delete-route --route-table-id "$rt" --destination-cidr-block "$c" && echo "  라우팅 삭제: $rt $c → $ep"
      done
    done
  done
  if nf delete-firewall --firewall-name "$SID-net-fw" >/dev/null; then
    echo "  방화벽 삭제 요청 (5~10분)"
    for _ in $(seq 1 60); do nf describe-firewall --firewall-name "$SID-net-fw" >/dev/null || { echo "  방화벽 삭제 완료"; break; }; sleep 15; done
  else
    echo "  ⚠️ 방화벽 삭제 실패: $(aws network-firewall delete-firewall --firewall-name "$SID-net-fw" 2>&1 | tail -1)"
  fi
fi
if nf describe-firewall-policy --firewall-policy-name "$SID-net-fw-policy" >/dev/null; then
  for _ in $(seq 1 18); do nf delete-firewall-policy --firewall-policy-name "$SID-net-fw-policy" >/dev/null && { echo "  방화벽 정책 삭제"; break; }; sleep 10; done
fi
for t in "STATEFUL $SID-net-fw-rules" "STATELESS $SID-net-fw-maint"; do
  set -- $t
  nf describe-rule-group --rule-group-name "$2" --type "$1" >/dev/null || continue
  for _ in $(seq 1 18); do nf delete-rule-group --rule-group-name "$2" --type "$1" >/dev/null && { echo "  규칙 그룹 삭제: $2"; break; }; sleep 10; done
done

# 3) TGW 연결 → TGW
for a in $(aws ec2 describe-transit-gateway-vpc-attachments --filters Name=tag:Owner,Values="$SID" Name=state,Values=available,pending,modifying,failed \
            --query "TransitGatewayVpcAttachments[?!(Tags[?Key=='$CFN'])].TransitGatewayAttachmentId" --output text); do
  aws ec2 delete-transit-gateway-vpc-attachment --transit-gateway-attachment-id "$a" >/dev/null && echo "  TGW 연결 삭제 요청: $a"
done
for _ in $(seq 1 40); do
  n=$(aws ec2 describe-transit-gateway-vpc-attachments --filters Name=tag:Owner,Values="$SID" Name=state,Values=deleting \
      --query 'length(TransitGatewayVpcAttachments)' --output text); [ "$n" = 0 ] && break; sleep 15
done
for t in $(aws ec2 describe-transit-gateways --filters Name=tag:Owner,Values="$SID" Name=state,Values=available,pending \
            --query "TransitGateways[?!(Tags[?Key=='$CFN'])].TransitGatewayId" --output text); do
  aws ec2 delete-transit-gateway --transit-gateway-id "$t" >/dev/null && echo "  TGW 삭제 요청: $t"
done

# 4) STS 엔드포인트 → 그 보안 그룹
if [ -n "$VPC" ] && [ "$VPC" != None ]; then
  for e in $(aws ec2 describe-vpc-endpoints --filters Name=vpc-id,Values="$VPC" \
              --query "VpcEndpoints[?ends_with(ServiceName,'.sts') && !(Tags[?Key=='$CFN'])].VpcEndpointId" --output text); do
    aws ec2 delete-vpc-endpoints --vpc-endpoint-ids "$e" >/dev/null && echo "  STS 엔드포인트 삭제 요청: $e"
    for _ in $(seq 1 24); do aws ec2 describe-vpc-endpoints --vpc-endpoint-ids "$e" --query 'VpcEndpoints[0].State' --output text 2>/dev/null | grep -qi delet || break; sleep 5; done
  done
  sg=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values="$VPC" Name=group-name,Values="$SID-net-vpce-sts-sg" \
        --query "SecurityGroups[?!(Tags[?Key=='$CFN'])].GroupId|[0]" --output text)
  if [ -n "$sg" ] && [ "$sg" != None ]; then
    for _ in $(seq 1 12); do aws ec2 delete-security-group --group-id "$sg" >/dev/null 2>&1 && { echo "  SG 삭제: $SID-net-vpce-sts-sg"; break; }; sleep 10; done
  fi
  # 5) 수강생이 만든 NACL: 서브넷 연결을 기본 NACL로 돌리고 지운다
  DEF=$(aws ec2 describe-network-acls --filters Name=vpc-id,Values="$VPC" Name=default,Values=true --query 'NetworkAcls[0].NetworkAclId' --output text)
  for acl in $(aws ec2 describe-network-acls --filters Name=vpc-id,Values="$VPC" Name=default,Values=false \
                --query "NetworkAcls[?!(Tags[?Key=='$CFN'])].NetworkAclId" --output text); do
    for as in $(aws ec2 describe-network-acls --network-acl-ids "$acl" --query 'NetworkAcls[0].Associations[].NetworkAclAssociationId' --output text); do
      aws ec2 replace-network-acl-association --association-id "$as" --network-acl-id "$DEF" >/dev/null
    done
    aws ec2 delete-network-acl --network-acl-id "$acl" && echo "  NACL 삭제: $acl"
  done
fi

# 6) 수강생이 만든 Flow Logs(두 VPC)와 로그 그룹
for v in $VPC $BASE; do
  [ "$v" = None ] && continue
  for f in $(aws ec2 describe-flow-logs --filter Name=resource-id,Values="$v" --query "FlowLogs[?!(Tags[?Key=='$CFN'])].FlowLogId" --output text); do
    aws ec2 delete-flow-logs --flow-log-ids "$f" >/dev/null && echo "  Flow Logs 삭제: $f"
  done
done
aws cloudformation describe-stacks --stack-name "$SID-net-done" >/dev/null 2>&1 && exit 0   # 완료 상태 스택이 로그 그룹을 지운다
for g in $(aws logs describe-log-groups --log-group-name-prefix "/opslab/$SID/net" --query 'logGroups[].logGroupName' --output text); do
  aws logs delete-log-group --log-group-name "$g" && echo "  로그 그룹 삭제: $g"
done
exit 0
