#!/bin/bash
# scale-3 drain — rollback(= 해답 조치). 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 드레인을 올바른 옵션으로 끝내고, 그 노드를 오토스케일링 그룹에서 종료해(원하는 수 유지) 새 노드로 교체한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
set +e
X=$(load drained)
if [ -n "$X" ] && [ "$X" != None ] && kubectl get node "$X" >/dev/null 2>&1; then
  kubectl drain "$X" --ignore-daemonsets --delete-emptydir-data --timeout=300s >/dev/null 2>&1 && echo "  드레인 완료: $X"
  IID=$(node_iid "$X")
  aws autoscaling terminate-instance-in-auto-scaling-group --instance-id "$IID" --no-should-decrement-desired-capacity >/dev/null && echo "  노드 교체 시작: $X ($IID)"
  for i in $(seq 1 60); do kubectl get node "$X" >/dev/null 2>&1 || break; sleep 10; done
  for i in $(seq 1 60); do [ "$(kubectl get nodes -l opslab/pool=default --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l)" -ge 2 ] && break; sleep 10; done
  echo "  관리형 노드 Ready $(kubectl get nodes -l opslab/pool=default --no-headers | awk '$2=="Ready"' | wc -l)대"
fi
restore
