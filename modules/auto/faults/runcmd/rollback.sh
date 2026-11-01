#!/bin/bash
# auto runcmd — rollback. ASG 의 모든 서버에 이름 태그를 다시 달고, 에이전트를 멈춘 변형(1)이면 기록된 서버를 재부팅한다
# (에이전트는 부팅 때 자동 시작). 에이전트를 막 멈춘 직후에는 PingStatus 가 Online 으로 남아 있어 상태로는 판단하지 않는다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
for x in $(asg_ids); do aws ec2 create-tags --resources "$x" --tags Key=Name,Value="$APP_TAG"; done; echo "  이름 태그 확인: $(asg_ids)"
I=$(load instance); V=$(load variant)
bad=""; for x in $(asg_ids); do [ "$(ping_of $x)" = Online ] || bad="$bad $x"; done
if [ "$V" = 1 ] && [ -n "$I" ] && [[ " $(asg_ids) " == *" $I "* ]]; then bad="$bad $I"; fi
bad=$(tr ' ' '\n' <<<"$bad" | sed '/^$/d' | sort -u | xargs)
if [ -n "$bad" ]; then
  aws ec2 reboot-instances --instance-ids $bad && echo "  재부팅: $bad"; sleep 45; T0=$(date -u +%s)
  for i in $(seq 1 36); do ok=1
    for x in $bad; do
      lp=$(aws ssm describe-instance-information --filters Key=InstanceIds,Values="$x" --query 'InstanceInformationList[0].LastPingDateTime' --output text 2>/dev/null)
      [ "$(ping_of $x)" = Online ] && [ "$(date -d "$lp" +%s 2>/dev/null || echo 0)" -gt "$T0" ] || ok=0
    done; [ $ok = 1 ] && { echo "  SSM 다시 연결됨"; break; }; sleep 10; done
fi
exit 0
