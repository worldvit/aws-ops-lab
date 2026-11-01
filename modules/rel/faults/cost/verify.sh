#!/bin/bash
# rel cost 판정 — ASG 2/2/4, ASG·부하 서버 외 EC2·연결 안 된 볼륨·놀고 있는 IP 없음, NAT 1개. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start cost
echo "[1] 과대·유휴 리소스"; chk_cost
echo "[2] 서비스"; chk_service
finish
