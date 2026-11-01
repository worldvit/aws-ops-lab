#!/bin/bash
# auto runcmd — rollback. ASG 의 모든 서버에 이름 태그를 다시 달고, 에이전트가 멈춘 서버는 ASG 로 교체한다.
# (재부팅은 ALB 헬스 체크 실패로 어차피 ASG 교체를 부르는 경우가 많다 — 리허설에서 확인) 새 서버가 SSM 에 붙을 때까지 기다린다.
# 에이전트를 막 멈춘 직후에는 PingStatus 가 Online 으로 남아 있어 상태로는 판단하지 않고, 기록된 변형으로 판단한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
for x in $(asg_ids); do aws ec2 create-tags --resources "$x" --tags Key=Name,Value="$APP_TAG"; done; echo "  이름 태그 확인: $(asg_ids)"
I=$(load instance); V=$(load variant)
bad=""; for x in $(asg_ids); do [ "$(ping_of $x)" = Online ] || bad="$bad $x"; done
if [ "$V" = 1 ] && [ -n "$I" ] && [[ " $(asg_ids) " == *" $I "* ]]; then bad="$bad $I"; fi
for x in $(tr ' ' '\n' <<<"$bad" | sed '/^$/d' | sort -u); do
  aws autoscaling terminate-instance-in-auto-scaling-group --instance-id "$x" --no-should-decrement-desired-capacity >/dev/null && echo "  ASG 교체: $x"
done
# ASG 의 InService 서버가 희망 수만큼 되고, 모두 SSM Online 일 때까지(최대 12분)
want=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" --query 'AutoScalingGroups[0].DesiredCapacity' --output text)
for i in $(seq 1 72); do ids=$(asg_ids); ok=1
  [ "$(wc -w <<<"$ids")" -ge "$want" ] || ok=0
  for x in $ids; do [[ " $bad " == *" $x "* ]] && ok=0; [ "$(ping_of $x)" = Online ] || ok=0; done
  [ $ok = 1 ] && { echo "  ASG ${want}대 모두 SSM 연결"; break; }; sleep 10; done
exit 0
