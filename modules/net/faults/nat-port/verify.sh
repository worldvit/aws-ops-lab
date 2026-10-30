#!/bin/bash
# net nat-port 판정 — 경로 ②(ALB IP별), NAT 포트 할당 오류 지표, 서버별 외부 80번 연결 수를 본다. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start nat-port
echo "[1] 경로 점검"; chk_nat
echo "[2] NAT 지표"; chk_natmetric
echo "[3] 서버별 외부(80번) 연결 수 — 평소에는 수십 개 이하"
while read -r h c; do
  [ -z "$h" ] && continue
  [ "${c:-0}" -lt 1000 ] && ok "$h 80번 연결 $c 개" || ng "$h 80번 연결 $c 개 (연결을 많이 여는 프로세스 확인)"
done < <(ssm_run "$(app_ids) $LOADGEN" "echo \$(hostname) \$(ss -Htn state established '( dport = :80 )' | wc -l)" 30)
aws cloudwatch describe-alarms --alarm-names "$SID-net-nat-port-alloc" --query 'MetricAlarms[0].AlarmName' --output text | grep -q "$SID" \
  && ok "NAT 포트 할당 오류 알람 있음" || ng "알람 $SID-net-nat-port-alloc 없음"
finish
