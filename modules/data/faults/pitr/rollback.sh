#!/bin/bash
# data pitr — rollback. 지운 행을 원래 값(초기 데이터 규칙)으로 다시 넣고, 복원 연습용 클러스터를 지운다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
need WRITER_EP LOADGEN
sql "INSERT INTO orders(id, item, qty) SELECT g, 'item-'||g, (g % 9) + 1 FROM generate_series(1,1000) g WHERE g % 3 = 0 ON CONFLICT DO NOTHING;
SELECT 'orders='||count(*) FROM orders;" | sed 's/^/  /'
for c in $(aws rds describe-db-clusters --query "DBClusters[?starts_with(DBClusterIdentifier,'$SID-data-restore')].DBClusterIdentifier" --output text); do
  for i in $(aws rds describe-db-instances --filters Name=db-cluster-id,Values="$c" --query 'DBInstances[].DBInstanceIdentifier' --output text); do
    aws rds delete-db-instance --db-instance-identifier "$i" --skip-final-snapshot >/dev/null 2>&1 && echo "  복원 인스턴스 삭제 요청: $i"
  done
  aws rds delete-db-cluster --db-cluster-identifier "$c" --skip-final-snapshot >/dev/null 2>&1 && echo "  복원 클러스터 삭제 요청: $c"
done
