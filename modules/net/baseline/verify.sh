#!/bin/bash
# net 정상 상태 정의(2단계) 판정 — 네 갈래 경로가 모두 되고, NAT 포트 할당 오류가 없어야 한다. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../check.sh"
start baseline
echo "[1] 경로 점검"; chk_user; chk_nat; chk_tgw; chk_sts
echo "[2] 지표"; chk_natmetric 5
echo "[3] 재발 방지 장치"
aws cloudwatch describe-alarms --alarm-names "$SID-net-nat-port-alloc" --query 'MetricAlarms[0].AlarmName' --output text | grep -q "$SID" \
  && ok "NAT 포트 할당 오류 알람 있음" || ng "알람 $SID-net-nat-port-alloc 없음 (1단계 1-9)"
finish
