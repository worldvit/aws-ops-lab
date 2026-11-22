#!/bin/bash
# scale 모듈 장애 스크립트 공통: 공통 함수 + EKS 함수 + scale 함수(functions.sh)
D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
source "$D/../../common/lib.sh"
source "$D/../../common/eks.sh"
kube_login || { echo "클러스터 $CLUSTER 에 접속하지 못했습니다."; exit 3; }
source "$D/functions.sh"
source "$EKS_ROOT/modules/cluster/node.sh"
kubectl -n "$APP_NS" get deploy opslab-app >/dev/null 2>&1 || { echo "샘플 앱이 없습니다. 환경 층(start.sh scale)을 먼저 배포하세요."; exit 3; }
hpa_json >/dev/null || { echo "HPA 가 없습니다. 1단계 구축 1을 먼저 끝내세요."; exit 3; }
np_json >/dev/null || { echo "Karpenter NodePool 이 없습니다. 1단계 구축 3을 먼저 끝내세요."; exit 3; }
# 영향 범위: app 네임스페이스(course=opslab)의 샘플 앱·HPA·실습용 Deployment(spike·batch·cache-worker)·PostgreSQL(StatefulSet·PVC),
#           kube-system 의 metrics-server(관리형 애드온) 파드 수, Karpenter NodePool·EC2NodeClass, 노드 cordon·드레인과 관리형 노드 그룹 노드 1대 교체.
#           강사/FIS 접근 항목·계정 IAM·다른 네임스페이스는 바꾸지 않는다.
set -e
restore() {  # 원복: 실습용 부하·배치 정지 → metrics-server·앱 요청·HPA·Karpenter 기준 상태 → cordon 해제 → DB(스냅샷 복원·노드 고정 해제)
  set +e
  local n
  spike stop; batch stop; kubectl -n "$APP_NS" delete deploy opslab-cache-worker opslab-idle --ignore-not-found --wait=false >/dev/null
  [ "$(kubectl -n kube-system get deploy metrics-server -o jsonpath='{.spec.replicas}' 2>/dev/null)" = 0 ] && kubectl -n kube-system scale deploy metrics-server --replicas=2 >/dev/null && echo "  metrics-server 다시 2개"
  helm -n "$APP_NS" upgrade opslab-app "$EKS_ROOT/charts/opslab-app" --reuse-values "${HPA_SET[@]}" --wait --timeout 5m >/dev/null && echo "  앱·HPA 를 기준 상태로(요청 100m·HPA 2~8·CPU 50%)"
  kp_nodes && echo "  Karpenter EC2NodeClass·NodePool 을 기준 상태로"
  for n in $(kubectl get nodes --no-headers | awk '$2 ~ /SchedulingDisabled/ {print $1}'); do kubectl uncordon "$n" >/dev/null && echo "  uncordon $n"; done
  if [ -n "$(kubectl -n "$APP_NS" get sts postgres -o jsonpath='{.spec.template.spec.nodeSelector}' 2>/dev/null)" ]; then
    kubectl -n "$APP_NS" patch sts postgres --type json -p '[{"op":"remove","path":"/spec/template/spec/nodeSelector"}]' >/dev/null
    kubectl -n "$APP_NS" delete pod postgres-0 --wait=false >/dev/null 2>&1; echo "  PostgreSQL 노드 고정 해제"
  fi
  kubectl -n "$APP_NS" rollout status sts postgres --timeout=300s >/dev/null 2>&1
  [ "$(pg_marker)" = scale-baseline ] || { pg_restore && echo "  PostgreSQL 디스크를 스냅샷(pg-baseline)에서 복원"; }
  kubectl -n "$APP_NS" rollout status deploy opslab-app --timeout=300s >/dev/null
  for n in $(seq 1 30); do [ -z "$(pending_pods)" ] && [ "$(nodes_ready)" -eq "$(kubectl get nodes --no-headers | wc -l)" ] && break; sleep 10; done
  echo "  노드 $(nodes_ready)대 Ready, Pending 파드 $(pending_pods | wc -l)개, HPA $(hpa_line)"
}
