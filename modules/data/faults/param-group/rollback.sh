#!/bin/bash
# data param-group — rollback. 바꾼 파라미터를 기본값으로 되돌리고, 재시작이 필요한 인스턴스는 재시작한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
need CPG
aws rds reset-db-cluster-parameter-group --db-cluster-parameter-group-name "$CPG" \
  --parameters ParameterName=default_transaction_read_only,ApplyMethod=immediate ParameterName=statement_timeout,ApplyMethod=immediate >/dev/null \
  && echo "  클러스터 파라미터 default_transaction_read_only·statement_timeout 기본값"
for g in $(aws rds describe-db-instances --filters Name=db-cluster-id,Values="$CLUSTER" --query 'DBInstances[].DBParameterGroups[0].DBParameterGroupName' --output text | tr '\t' '\n' | sort -u); do
  aws rds reset-db-parameter-group --db-parameter-group-name "$g" --parameters ParameterName=max_connections,ApplyMethod=pending-reboot >/dev/null 2>&1 \
    && echo "  인스턴스 파라미터 그룹 $g: max_connections 기본값"
done
wait_cluster 600
sleep 15
for i in $(aws rds describe-db-instances --filters Name=db-cluster-id,Values="$CLUSTER" \
            --query "DBInstances[?DBParameterGroups[0].ParameterApplyStatus=='pending-reboot'].DBInstanceIdentifier" --output text); do
  aws rds reboot-db-instance --db-instance-identifier "$i" >/dev/null && echo "  재시작: $i (파라미터 적용)"
done
wait_cluster 900 && echo "  클러스터 available"
