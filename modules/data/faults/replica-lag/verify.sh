#!/bin/bash
# data replica-lag 판정 — 리더 읽기, 복제 지연 지표(가장 최근 1분), 대량 작업 여부. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start replica-lag
echo "[1] 앱 → DB"; chk_app "/db?ro=1" "읽기(/db?ro=1)"
echo "[2] 복제 지연"
L=$(aws cloudwatch get-metric-statistics --namespace AWS/RDS --metric-name AuroraReplicaLagMaximum --dimensions Name=DBClusterIdentifier,Value="$CLUSTER" \
  --start-time "$(date -u -d '-5 min' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" --period 60 --statistics Maximum \
  --query 'sort_by(Datapoints,&Timestamp)[-1].Maximum' --output text | sed 's/None/0/')
awk "BEGIN{exit !(${L:-0} < 200)}" && ok "AuroraReplicaLagMaximum 가장 최근 1분 ${L}ms (200ms 미만)" || ng "AuroraReplicaLagMaximum 가장 최근 1분 ${L}ms (200ms 미만이어야 함)"
chk_jobs order-import report-analytics
finish
