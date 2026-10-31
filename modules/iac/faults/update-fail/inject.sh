#!/bin/bash
# iac update-fail — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: 스택 $STACK 업데이트(릴리스 v2) 1회 + 충돌을 일으키는 수동 리소스 1개(SG 또는 리스너 규칙).
need_stack
[ "$(stack_status)" = UPDATE_ROLLBACK_FAILED ] && exit 1
save prev_promo "$(sparam PromoText)"
V_=$(pick_variant 2)
case $V_ in
  1) # 릴리스 v2: 관리용 SG 이름을 새 규칙(-v2)으로 — 그런데 누군가 콘솔에서 같은 이름의 SG 를 먼저 만들어 둠
     aws ec2 create-security-group --group-name "$SID-iac-admin-sg-v2" --description "created manually" \
       --vpc-id "$(aws cloudformation list-exports --query "Exports[?Name=='$SID-base-VpcId'].Value" --output text)" \
       --tag-specifications "ResourceType=security-group,Tags=[{Key=Course,Value=opslab},{Key=Module,Value=iac},{Key=Owner,Value=$SID}]" >/dev/null || exit 1
     deploy_app PromoText=v2 AdminSgName="$SID-iac-admin-sg-v2" ;;
  2) # 릴리스 v2: /promo 규칙 우선순위를 20 으로 — 그런데 누군가 같은 리스너에 우선순위 20 규칙을 먼저 만들어 둠
     aws elbv2 create-rule --listener-arn "$(listener_arn)" --priority 20 --conditions Field=path-pattern,Values=/event \
       --actions 'Type=fixed-response,FixedResponseConfig={StatusCode=200,ContentType=text/plain,MessageBody=event}' \
       --tags Key=Course,Value=opslab Key=Module,Value=iac Key=Owner,Value=$SID >/dev/null || exit 1
     deploy_app PromoText=v2 RulePriority=20 ;;
esac
[ "$(wait_stack)" = UPDATE_ROLLBACK_COMPLETE ] || exit 1
record $V_
