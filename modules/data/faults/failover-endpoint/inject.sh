#!/bin/bash
# data failover-endpoint — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: 앱 접속정보 /opslab/app/db/host 와 Aurora 페일오버(라이터 ↔ 리더 교대)
need WRITER_EP READER_EP WRITER_ID READER_ID
V=$(pick_variant 2)
save prev_host "$(pget host)"
case $V in
  1) pput host "$(aws rds describe-db-instances --db-instance-identifier "$WRITER_ID" --query 'DBInstances[0].Endpoint.Address' --output text)" ;;  # 인스턴스 엔드포인트
  2) pput host "$READER_EP" ;;                                                                                                              # 리더 엔드포인트
esac || exit 1
sleep 35   # 앱 서버가 새 접속정보를 내려받는 주기(30초)
aws rds failover-db-cluster --db-cluster-identifier "$CLUSTER" --target-db-instance-identifier "$READER_ID" >/dev/null || exit 1
record $V
