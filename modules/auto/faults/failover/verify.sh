#!/bin/bash
# auto failover 판정 — 헬스 체크 설정·판정 정상, 주 레코드에 연결, DNS 가 주 서비스(ALB)를 가리킴. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start failover
echo "[1] 헬스 체크와 DNS"; chk_failover
finish
