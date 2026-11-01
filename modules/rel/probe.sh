#!/bin/bash
# rel 관찰 도구 — CloudShell 에서 5초마다 /api·/db 응답 코드와 앱 서버 AZ·DB 라이터 AZ 를 한 줄로 찍는다(Ctrl+C 로 끝).
#   bash ~/opslab/modules/rel/probe.sh
# 부하 서버(loadgen)는 AZ-a 앱 서브넷에 있어 AZ 장애 훈련 중에는 쓸 수 없으므로, 인터넷 쪽(CloudShell)에서 본다.
source ~/opslab-env.sh; REL_NO_LAB=1 source "$(dirname "$(readlink -f "$0")")/lib.sh"
n=0
while true; do
  [ $((n % 6)) -eq 0 ] && { W=$(writer_az); A=$(asg_azs); }
  echo "$(date +%T)  /api $(code_of /api)  /db $(code_of /db)   앱 서버[$A]  라이터 $W"
  n=$((n+1)); sleep 5
done
