#!/bin/bash
# net firewall-block 판정 — 경로 ③, 방화벽 규칙과 정책, 방화벽 동기화 상태를 본다. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start firewall-block
echo "[1] 경로 점검"; chk_tgw
echo "[2] 방화벽 규칙과 정책"
R=$(aws network-firewall describe-rule-group --rule-group-arn "$FW_RULES_ARN" --query 'RuleGroup.RulesSource.StatefulRules[?Action==`PASS`].Header' --output json 2>/dev/null)
jq -e 'any(.[]; .Protocol=="TCP" and .DestinationPort=="8080" and (.Source=="10.0.0.0/16" or .Source=="ANY"))' <<<"$R" >/dev/null \
  && ok "상태 저장 규칙: 10.0.0.0/16 → 8080 허용(PASS) 있음" || ng "상태 저장 규칙에 10.0.0.0/16 → 8080 허용(PASS) 없음: $(jq -c 'map({Source,DestinationPort})' <<<"$R")"
n=$(aws network-firewall describe-firewall-policy --firewall-policy-arn "$FW_POLICY_ARN" --query 'length(FirewallPolicy.StatelessRuleGroupReferences || `[]`)' --output text)
[ "$n" -eq 0 ] && ok "정책에 무상태 규칙 그룹 없음" || ng "정책에 무상태 규칙 그룹 $n 개 — 내용 확인"
S=$(aws network-firewall describe-firewall --firewall-name "$SID-net-fw" --query 'FirewallStatus.ConfigurationSyncStateSummary' --output text 2>/dev/null)
[ "$S" = IN_SYNC ] && ok "방화벽 설정 동기화 IN_SYNC" || ng "방화벽 설정 동기화 ${S:-확인 불가} (반영 중이면 1~2분 뒤 다시)"
finish
