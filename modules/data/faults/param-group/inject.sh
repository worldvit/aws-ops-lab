#!/bin/bash
# data param-group — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: 클러스터 파라미터 그룹(<학번>-data-cpg) 또는 인스턴스 파라미터 그룹(<학번>-data-ipg)과 라이터 재시작
need CPG WRITER_ID
IPG=$(aws rds describe-db-instances --db-instance-identifier "$WRITER_ID" --query 'DBInstances[0].DBParameterGroups[0].DBParameterGroupName' --output text)
save ipg "$IPG"
V=$(pick_variant 3)
case $V in
  1) aws rds modify-db-cluster-parameter-group --db-cluster-parameter-group-name "$CPG" \
       --parameters ParameterName=default_transaction_read_only,ParameterValue=on,ApplyMethod=immediate >/dev/null ;;
  2) aws rds modify-db-cluster-parameter-group --db-cluster-parameter-group-name "$CPG" \
       --parameters ParameterName=statement_timeout,ParameterValue=1,ApplyMethod=immediate >/dev/null ;;
  3) aws rds modify-db-parameter-group --db-parameter-group-name "$IPG" \
       --parameters ParameterName=max_connections,ParameterValue=6,ApplyMethod=pending-reboot >/dev/null &&
     sleep 15 && wait_cluster 600 &&       # 파라미터 그룹 변경 직후 인스턴스는 잠시 modifying(applying) — 끝난 뒤 재시작
     aws rds reboot-db-instance --db-instance-identifier "$WRITER_ID" >/dev/null ;;
esac || exit 1
record $V
