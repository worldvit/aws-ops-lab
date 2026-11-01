#!/bin/bash
# auto runcmd — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: 앱 서버 1대(ASG 의 첫 InService)의 SSM 에이전트(v1) 또는 이름 태그(v2). 앱 서비스는 그대로 동작한다.
I=$(asg_ids | awk '{print $1}'); [ -n "$I" ] || exit 3
save instance "$I"
V_=$(pick_variant 2)
case $V_ in
  1) # 그 서버의 SSM 에이전트가 멈춤(디스크 정리 스크립트가 잘못 멈춘 상황)
     ssm_run "$I" "nohup bash -c 'sleep 3; systemctl stop amazon-ssm-agent' >/dev/null 2>&1 & echo scheduled" 30 >/dev/null ;;
  2) # 자산 정리 중 그 서버의 Name 태그가 지워짐
     aws ec2 delete-tags --resources "$I" --tags Key=Name >/dev/null || exit 1 ;;
esac
record $V_
