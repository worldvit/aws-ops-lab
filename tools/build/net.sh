#!/bin/bash
# net 모듈 1단계 따라하기 명령 모음 — Notion 페이지의 명령과 같다. 작성자가 따라하기 명령을 한 번에 검증할 때 쓴다.
#   source ~/opslab-env.sh && bash ~/opslab/common/start.sh net && source ~/opslab-env.sh && bash ~/opslab/tools/build/net.sh
# 수강생은 이 파일을 실행하지 않고, 페이지의 명령을 한 단계씩 실행하며 확인한다.
set -euo pipefail
source ~/opslab-env.sh
tags() { echo "ResourceType=$1,Tags=[{Key=Name,Value=$2},{Key=Course,Value=opslab},{Key=Module,Value=net},{Key=Owner,Value=$SID}]"; }
nftags() { echo "Key=Name,Value=$1 Key=Course,Value=opslab Key=Module,Value=net Key=Owner,Value=$SID"; }

echo "== 1-2 Network Firewall 만들기 시작 (5~10분, 기다리지 않고 다음 단계 진행)"
cat > ~/fw-rules.json <<'EOF'
{"RulesSource": {"StatefulRules": [
  {"Action": "PASS",
   "Header": {"Protocol": "TCP", "Source": "10.0.0.0/16", "SourcePort": "ANY", "Direction": "FORWARD",
              "Destination": "10.20.2.0/24", "DestinationPort": "8080"},
   "RuleOptions": [{"Keyword": "sid", "Settings": ["1"]}]},
  {"Action": "DROP",
   "Header": {"Protocol": "IP", "Source": "ANY", "SourcePort": "ANY", "Direction": "ANY",
              "Destination": "ANY", "DestinationPort": "ANY"},
   "RuleOptions": [{"Keyword": "sid", "Settings": ["2"]}]}]}}
EOF
FW_RULES_ARN=$(aws network-firewall create-rule-group --rule-group-name $SID-net-fw-rules --type STATEFUL --capacity 100 \
  --rule-group file://$HOME/fw-rules.json --tags $(nftags $SID-net-fw-rules) --query RuleGroupResponse.RuleGroupArn --output text)
FW_POLICY_ARN=$(aws network-firewall create-firewall-policy --firewall-policy-name $SID-net-fw-policy \
  --firewall-policy "{\"StatelessDefaultActions\":[\"aws:forward_to_sfe\"],\"StatelessFragmentDefaultActions\":[\"aws:forward_to_sfe\"],\"StatefulRuleGroupReferences\":[{\"ResourceArn\":\"$FW_RULES_ARN\"}]}" \
  --tags $(nftags $SID-net-fw-policy) --query FirewallPolicyResponse.FirewallPolicyArn --output text)
aws network-firewall create-firewall --firewall-name $SID-net-fw --firewall-policy-arn $FW_POLICY_ARN \
  --vpc-id $NET_VPC_ID --subnet-mappings SubnetId=$NET_FW_SUBNET --tags $(nftags $SID-net-fw) \
  --query 'Firewall.FirewallName' --output text

echo "== 1-3 Transit Gateway와 VPC 연결 2개"
TGW_ID=$(aws ec2 create-transit-gateway --description "opslab net" \
  --options DefaultRouteTableAssociation=enable,DefaultRouteTablePropagation=enable \
  --tag-specifications "$(tags transit-gateway $SID-net-tgw)" --query TransitGateway.TransitGatewayId --output text)
until [ "$(aws ec2 describe-transit-gateways --transit-gateway-ids $TGW_ID --query 'TransitGateways[0].State' --output text)" = available ]; do sleep 10; done
echo "TGW 준비 완료: $TGW_ID"
ATT_BASE=$(aws ec2 create-transit-gateway-vpc-attachment --transit-gateway-id $TGW_ID --vpc-id $VPC_ID \
  --subnet-ids ${APP_SUBNETS//,/ } --tag-specifications "$(tags transit-gateway-attachment $SID-net-tgw-att-base)" \
  --query TransitGatewayVpcAttachment.TransitGatewayAttachmentId --output text)
ATT_NET=$(aws ec2 create-transit-gateway-vpc-attachment --transit-gateway-id $TGW_ID --vpc-id $NET_VPC_ID \
  --subnet-ids $NET_TGW_SUBNET --tag-specifications "$(tags transit-gateway-attachment $SID-net-tgw-att-net)" \
  --query TransitGatewayVpcAttachment.TransitGatewayAttachmentId --output text)
until [ "$(aws ec2 describe-transit-gateway-vpc-attachments --transit-gateway-attachment-ids $ATT_BASE $ATT_NET \
  --query 'length(TransitGatewayVpcAttachments[?State==`available`])' --output text)" = 2 ]; do sleep 10; done
echo "export TGW_ID=$TGW_ID ATT_BASE=$ATT_BASE ATT_NET=$ATT_NET" >> ~/opslab-env.sh

echo "== 1-4 라우팅 (방화벽 없이 먼저 연결)"
aws ec2 create-route --route-table-id $APP_ROUTE_TABLE --destination-cidr-block 10.20.0.0/16 --transit-gateway-id $TGW_ID >/dev/null
aws ec2 create-route --route-table-id $NET_SVC_RT --destination-cidr-block 10.0.0.0/16 --transit-gateway-id $TGW_ID >/dev/null
aws ec2 describe-transit-gateway-route-tables --filters Name=transit-gateway-id,Values=$TGW_ID --query 'TransitGatewayRouteTables[0].TransitGatewayRouteTableId' --output text \
  | xargs -I{} aws ec2 search-transit-gateway-routes --transit-gateway-route-table-id {} --filters Name=state,Values=active \
      --query 'Routes[].[DestinationCidrBlock,TransitGatewayAttachments[0].ResourceId,Type]' --output table

echo "== 1-5 PrivateLink: STS 인터페이스 엔드포인트"
STS_SG=$(aws ec2 create-security-group --group-name $SID-net-vpce-sts-sg --description "STS endpoint - 443 from net VPC" \
  --vpc-id $NET_VPC_ID --tag-specifications "$(tags security-group $SID-net-vpce-sts-sg)" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id $STS_SG --protocol tcp --port 443 --cidr 10.20.0.0/16 >/dev/null
aws ec2 create-vpc-endpoint --vpc-id $NET_VPC_ID --vpc-endpoint-type Interface --service-name com.amazonaws.$AWS_REGION.sts \
  --subnet-ids $NET_SVC_SUBNET --security-group-ids $STS_SG --private-dns-enabled \
  --tag-specifications "$(tags vpc-endpoint $SID-net-vpce-sts)" --query 'VpcEndpoint.[VpcEndpointId,State]' --output text

echo "== 1-6 서비스 서브넷 NACL"
NACL_ID=$(aws ec2 create-network-acl --vpc-id $NET_VPC_ID --tag-specifications "$(tags network-acl $SID-net-svc-nacl)" \
  --query NetworkAcl.NetworkAclId --output text)
aws ec2 create-network-acl-entry --network-acl-id $NACL_ID --ingress --rule-number 100 --protocol tcp --port-range From=8080,To=8080 --cidr-block 10.0.0.0/16 --rule-action allow
aws ec2 create-network-acl-entry --network-acl-id $NACL_ID --ingress --rule-number 200 --protocol -1 --cidr-block 10.20.0.0/16 --rule-action allow
aws ec2 create-network-acl-entry --network-acl-id $NACL_ID --egress  --rule-number 100 --protocol tcp --port-range From=1024,To=65535 --cidr-block 10.0.0.0/16 --rule-action allow
aws ec2 create-network-acl-entry --network-acl-id $NACL_ID --egress  --rule-number 200 --protocol -1 --cidr-block 10.20.0.0/16 --rule-action allow
ASSOC=$(aws ec2 describe-network-acls --filters Name=association.subnet-id,Values=$NET_SVC_SUBNET \
  --query "NetworkAcls[0].Associations[?SubnetId=='$NET_SVC_SUBNET'].NetworkAclAssociationId" --output text)
aws ec2 replace-network-acl-association --association-id $ASSOC --network-acl-id $NACL_ID >/dev/null

echo "== 1-7 방화벽을 경로에 끼우기"
until [ "$(aws network-firewall describe-firewall --firewall-name $SID-net-fw --query 'FirewallStatus.Status' --output text)" = READY ]; do sleep 15; done
FW_EP=$(aws network-firewall describe-firewall --firewall-name $SID-net-fw --query 'FirewallStatus.SyncStates.*.Attachment.EndpointId' --output text)
echo "방화벽 엔드포인트: $FW_EP"
aws logs create-log-group --log-group-name /opslab/$SID/net-fw
aws logs put-retention-policy --log-group-name /opslab/$SID/net-fw --retention-in-days 1
aws network-firewall update-logging-configuration --firewall-name $SID-net-fw \
  --logging-configuration "{\"LogDestinationConfigs\":[{\"LogType\":\"ALERT\",\"LogDestinationType\":\"CloudWatchLogs\",\"LogDestination\":{\"logGroup\":\"/opslab/$SID/net-fw\"}}]}" >/dev/null
aws ec2 create-route  --route-table-id $NET_TGW_RT --destination-cidr-block 10.20.2.0/24 --vpc-endpoint-id $FW_EP >/dev/null
aws ec2 replace-route --route-table-id $NET_SVC_RT --destination-cidr-block 10.0.0.0/16  --vpc-endpoint-id $FW_EP
aws ec2 create-route  --route-table-id $NET_FW_RT  --destination-cidr-block 10.0.0.0/16  --transit-gateway-id $TGW_ID >/dev/null

echo "== 1-8 VPC Flow Logs (두 VPC)"
aws logs create-log-group --log-group-name /opslab/$SID/net-flowlogs
aws logs put-retention-policy --log-group-name /opslab/$SID/net-flowlogs --retention-in-days 1
aws ec2 create-flow-logs --resource-type VPC --resource-ids $VPC_ID $NET_VPC_ID --traffic-type ALL \
  --log-destination-type cloud-watch-logs --log-group-name /opslab/$SID/net-flowlogs \
  --deliver-logs-permission-arn $FLOW_LOGS_ROLE_ARN --max-aggregation-interval 60 \
  --tag-specifications "$(tags vpc-flow-log $SID-net-flow)" --query 'FlowLogIds' --output text

echo "== 1-9 재발 방지: NAT 포트 할당 오류 알람"
aws cloudwatch put-metric-alarm --alarm-name $SID-net-nat-port-alloc --namespace AWS/NATGateway --metric-name ErrorPortAllocation \
  --dimensions Name=NatGatewayId,Value=$NAT_ID --statistic Sum --period 60 --evaluation-periods 1 --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold --treat-missing-data notBreaching \
  --tags Key=Course,Value=opslab Key=Module,Value=net Key=Owner,Value=$SID
echo "✅ 1단계 명령 완료"
