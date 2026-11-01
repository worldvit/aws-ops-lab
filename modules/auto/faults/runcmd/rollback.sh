#!/bin/bash
# auto runcmd — rollback. ASG 의 모든 서버에 이름 태그를 다시 달고, SSM 연결이 끊긴 서버는 재부팅(에이전트는 부팅 시 자동 시작).
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
for x in $(asg_ids); do aws ec2 create-tags --resources "$x" --tags Key=Name,Value="$APP_TAG"; done; echo "  이름 태그 확인: $(asg_ids)"
bad=""; for x in $(asg_ids); do [ "$(ping_of $x)" = Online ] || bad="$bad $x"; done
# 에이전트를 막 멈춘 직후에는 아직 Online 으로 보일 수 있다 — 기록된 서버에 Run Command 가 도는지로 확인
I=$(load instance); if [ -n "$I" ] && [[ " $(asg_ids) " == *" $I "* ]]; then
  [ -n "$(ssm_run "$I" 'echo alive' 20 | grep alive)" ] || bad="$bad $I"; fi
bad=$(tr ' ' '\n' <<<"$bad" | sort -u | xargs)
if [ -n "$bad" ]; then aws ec2 reboot-instances --instance-ids $bad && echo "  재부팅: $bad"
  for i in $(seq 1 30); do ok=1; for x in $bad; do [ "$(ping_of $x)" = Online ] || ok=0; done; [ $ok = 1 ] && break; sleep 10; done; fi
exit 0
