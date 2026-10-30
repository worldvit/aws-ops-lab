#!/bin/bash
# data param-group 판정 — 앱 쓰기, 사용자가 바꾼 파라미터, 재시작 대기 상태. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start param-group
echo "[1] 앱 → DB"; chk_app /db "쓰기(/db)"
echo "[2] 파라미터 그룹"
U=$(aws rds describe-db-cluster-parameters --db-cluster-parameter-group-name "$CPG" --source user \
     --query "Parameters[?ParameterName=='default_transaction_read_only' || ParameterName=='statement_timeout'].[ParameterName,ParameterValue]" --output text)
[ -z "$U" ] && ok "클러스터 파라미터 그룹: read_only·statement_timeout 기본값" || ng "클러스터 파라미터 그룹에서 바뀐 값: $(tr '\t\n' '= ' <<<"$U")"
for g in $(aws rds describe-db-instances --filters Name=db-cluster-id,Values="$CLUSTER" --query 'DBInstances[].DBParameterGroups[0].DBParameterGroupName' --output text | tr '\t' '\n' | sort -u); do
  m=$(aws rds describe-db-parameters --db-parameter-group-name "$g" --source user --query "Parameters[?ParameterName=='max_connections'].ParameterValue" --output text)
  [ -z "$m" ] && ok "인스턴스 파라미터 그룹 $g: max_connections 기본값" || ng "인스턴스 파라미터 그룹 $g: max_connections=$m"
done
P2=$(aws rds describe-db-instances --filters Name=db-cluster-id,Values="$CLUSTER" --query "DBInstances[].[DBInstanceIdentifier,DBParameterGroups[0].ParameterApplyStatus]" --output text | grep -v in-sync | tr '\t\n' '= ')
[ -z "$P2" ] && ok "모든 인스턴스 파라미터 적용 상태 in-sync" || ng "파라미터 적용 대기: $P2"
finish
