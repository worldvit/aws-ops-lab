#!/bin/bash
# heal-5 repair — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: 노드 그룹 자동 복구 설정, 노드의 kubelet(PostgreSQL 이 없는 노드만)
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 2); base_save
PG=$(pg_node)
OTHERS=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep -vx "${PG:-none}")
case $V in
  1) # 자동 복구가 꺼진 노드 그룹에서 노드 하나의 kubelet 이 멈췄다(감지는 되나 아무도 교체하지 않음)
     ng_wait; aws eks update-nodegroup-config --cluster-name "$CLUSTER" --nodegroup-name "$NG" --node-repair-config enabled=false >/dev/null; ng_wait
     N=$(echo "$OTHERS" | head -1); save broken "$N"
     on_node "$N" "systemctl stop kubelet" >/dev/null || true ;;
  2) # 교체 범위 제한을 "풀어" 둔 상태에서, 잘못된 설정 배포로 노드 2대의 kubelet 이 함께 멈췄다 → 자동 복구가 한꺼번에 교체
     ng_wait; aws eks update-nodegroup-config --cluster-name "$CLUSTER" --nodegroup-name "$NG" \
       --node-repair-config '{"enabled":true,"maxUnhealthyNodeThresholdPercentage":100,"maxParallelNodesRepairedPercentage":100}' >/dev/null; ng_wait
     save broken "$(echo $OTHERS)"
     for N in $OTHERS; do on_node "$N" "systemctl stop kubelet" >/dev/null || true; done ;;
esac
record $V
