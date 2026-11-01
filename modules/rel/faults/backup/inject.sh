#!/bin/bash
# rel backup — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: Aurora 클러스터 $CLUSTER 의 백업 보존 기간(v1) 또는 삭제 방지(v2). 데이터와 서비스는 그대로.
V_=$(pick_variant 2)
case $V_ in
  1) # 스토리지 비용을 줄인다며 백업 보존을 1일로 줄임
     aws rds modify-db-cluster --db-cluster-identifier "$CLUSTER" --backup-retention-period 1 --apply-immediately >/dev/null || exit 1 ;;
  2) # 정리 작업 중 삭제 방지를 끄고 되돌리지 않음
     aws rds modify-db-cluster --db-cluster-identifier "$CLUSTER" --no-deletion-protection --apply-immediately >/dev/null || exit 1 ;;
esac
record $V_
