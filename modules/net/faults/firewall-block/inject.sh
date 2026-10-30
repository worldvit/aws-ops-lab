#!/bin/bash
# net firewall-block — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: 방화벽 규칙 그룹($SID-net-fw-rules)과 방화벽 정책($SID-net-fw-policy)만. 변형 3은 규칙 그룹 1개를 새로 만든다.
need FW_RULES_ARN FW_POLICY_ARN
V=$(pick_variant 3)
case $V in
  1) fw_set_rules 8008 10.0.0.0/16 ;;           # 허용 규칙의 포트 오타
  2) fw_set_rules 8080 10.10.0.0/16 ;;          # 허용 규칙의 출발지 오류
  3) RG='{"RulesSource":{"StatelessRulesAndCustomActions":{"StatelessRules":[{"Priority":1,"RuleDefinition":{"MatchAttributes":{"Sources":[{"AddressDefinition":"0.0.0.0/0"}],"Destinations":[{"AddressDefinition":"10.20.2.0/24"}],"DestinationPorts":[{"FromPort":8080,"ToPort":8080}],"Protocols":[6]},"Actions":["aws:drop"]}}]}}}'
     ARN=$(aws network-firewall create-rule-group --rule-group-name "$SID-net-fw-maint" --type STATELESS --capacity 10 \
       --description "maintenance block list" --rule-group "$RG" \
       --tags Key=Name,Value="$SID-net-fw-maint" Key=Course,Value=opslab Key=Module,Value=net Key=Owner,Value="$SID" \
       --query RuleGroupResponse.RuleGroupArn --output text) &&
     fw_policy_edit ".StatelessRuleGroupReferences=[{ResourceArn:\"$ARN\",Priority:10}]" ;;
esac || exit 1
record $V
