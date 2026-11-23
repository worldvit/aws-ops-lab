#!/bin/bash
# scale-5 data — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: app 네임스페이스 PostgreSQL(StatefulSet·PVC data-postgres-0) — 스냅샷 pg-baseline 은 건드리지 않는다
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 2)
case $V in
  1) # "디스크 정리" 중 PostgreSQL 의 PVC 를 지웠다 — StatefulSet 이 빈 디스크를 새로 만들어 DB 가 처음부터 시작한다
     kubectl -n "$APP_NS" scale sts postgres --replicas=0 >/dev/null; kubectl -n "$APP_NS" wait --for=delete pod/postgres-0 --timeout=120s >/dev/null 2>&1 || true
     kubectl -n "$APP_NS" delete pvc data-postgres-0 --wait=true --timeout=120s >/dev/null
     kubectl -n "$APP_NS" scale sts postgres --replicas=1 >/dev/null
     kubectl -n "$APP_NS" rollout status sts postgres --timeout=300s >/dev/null || true ;;
  2) # "AZ 간 전송 비용 절감"으로 DB 를 다른 AZ 노드로 옮기려 nodeSelector 를 넣었다 — EBS 는 원래 AZ 에 묶여 있다
     N=$(kubectl -n "$APP_NS" get pod postgres-0 -o jsonpath='{.spec.nodeName}')
     Z=$(kubectl get node "$N" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}')
     O=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.labels.topology\.kubernetes\.io/zone}{"\n"}{end}' | sort -u | grep -v "^$Z$" | head -1)
     save zone "$Z"
     kubectl -n "$APP_NS" patch sts postgres --type merge -p "{\"spec\":{\"template\":{\"spec\":{\"nodeSelector\":{\"topology.kubernetes.io/zone\":\"$O\"}}}}}" >/dev/null
     kubectl -n "$APP_NS" delete pod postgres-0 --wait=false >/dev/null ;;
esac
record $V
