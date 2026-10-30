#!/bin/bash
# data failover-endpoint — rollback. 앱 접속정보를 클러스터(라이터) 엔드포인트로 되돌린다. 라이터 위치는 되돌리지 않는다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
need WRITER_EP
pput host "$WRITER_EP" && echo "  앱 접속정보 host → 클러스터 엔드포인트"
wait_cluster 600 && echo "  클러스터 available" || echo "  ⚠️ 클러스터가 아직 available 이 아님"
sleep 35
