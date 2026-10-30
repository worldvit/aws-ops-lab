#!/bin/bash
# net firewall-block — rollback. 규칙 그룹을 정상 규칙으로 다시 쓰고, 정책에 붙은 무상태 규칙 그룹을 떼어 지운다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
need FW_RULES_ARN FW_POLICY_ARN
fw_set_rules 8080 10.0.0.0/16 && echo "  상태 저장 규칙 그룹 정상 규칙으로 복원"
n=$(aws network-firewall describe-firewall-policy --firewall-policy-arn "$FW_POLICY_ARN" --query 'length(FirewallPolicy.StatelessRuleGroupReferences || `[]`)' --output text)
[ "$n" -gt 0 ] && fw_policy_edit 'del(.StatelessRuleGroupReferences)' && echo "  정책에서 무상태 규칙 그룹 분리"
for _ in $(seq 1 12); do   # 정책 변경이 방화벽에 반영되어야 규칙 그룹을 지울 수 있다
  aws network-firewall describe-rule-group --rule-group-name "$SID-net-fw-maint" --type STATELESS >/dev/null 2>&1 || break
  aws network-firewall delete-rule-group --rule-group-name "$SID-net-fw-maint" --type STATELESS >/dev/null 2>&1 && { echo "  규칙 그룹 $SID-net-fw-maint 삭제"; break; }
  sleep 10
done
