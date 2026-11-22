#!/bin/bash
# scale 상태 조회 도우미 — review.yaml·check.sh 가 부른다.  bash ~/opslab/modules/scale/state.sh <질문>
#   hpa      : metrics-server Ready + HPA 대상 존재 + 최소<최대 + CPU 사용률을 읽음 + 앱 CPU 요청 있음이면 0
#   karpenter: 컨트롤러 Ready + NodePool·EC2NodeClass Ready + 한도 16 + 크기 조건 large·xlarge 면 0
#   pending  : Pending 파드가 없으면 0
#   nodes    : 노드 전부 Ready, cordon 없음이면 0
#   replaced : scale-3 에서 드레인하던 노드가 교체됐으면(클러스터에 없으면) 0
#   db       : PostgreSQL Running + 기준 데이터(마커) + PostgreSQL 에 노드 고정 없음이면 0
set -uo pipefail
: "${SID:?}"; source "$(dirname "$(readlink -f "$0")")/../../common/eks.sh"; kube_login
source "$EKS_ROOT/modules/scale/functions.sh"
case "${1:-}" in
  hpa) h=$(hpa_json) || { echo "HPA 없음"; exit 1; }
       [ "$(kubectl -n kube-system get deploy metrics-server -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)" -ge 1 ] || { echo "metrics-server Ready 0"; exit 1; }
       jq -e '.spec.scaleTargetRef.name=="opslab-app" and .spec.maxReplicas > .spec.minReplicas and (.status.currentMetrics[0].resource.current.averageUtilization != null)' <<<"$h" >/dev/null \
         || { echo "HPA $(jq -c '{target:.spec.scaleTargetRef.name,min:.spec.minReplicas,max:.spec.maxReplicas,cur:.status.currentMetrics}' <<<"$h")"; exit 1; }
       [ -n "$(kubectl -n "$APP_NS" get deploy opslab-app -o jsonpath='{.spec.template.spec.containers[?(@.name=="app")].resources.requests.cpu}')" ] || { echo "CPU 요청 없음"; exit 1; } ;;
  karpenter) [ "$(kubectl -n kube-system get deploy karpenter -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)" -ge 1 ] && kp_ready \
       && [ "$(np_json | jq -r '.spec.limits.cpu')" = 16 ] \
       && [ "$(np_json | jq -r '[.spec.template.spec.requirements[]|select(.key=="karpenter.k8s.aws/instance-size")|.values]|flatten|sort|join(",")')" = large,xlarge ] \
       && [ "$(nc_json | jq -r '.spec.subnetSelectorTerms[0].tags["karpenter.sh/discovery"]')" = "$SID" ] \
       || { echo "NodePool $(np_json | jq -c '{limits:.spec.limits,ready:[.status.conditions[]?|select(.type=="Ready")|.status]}') EC2NodeClass $(nc_json | jq -c '{subnet:.spec.subnetSelectorTerms,ready:[.status.conditions[]?|select(.type=="Ready")|.status]}')"; exit 1; } ;;
  pending) p=$(pending_pods); [ -z "$p" ] || { echo "$p"; exit 1; } ;;
  nodes) [ "$(nodes_ready)" -ge 2 ] && [ "$(nodes_ready)" -eq "$(kubectl get nodes --no-headers | wc -l)" ] && ! kubectl get nodes --no-headers | grep -q SchedulingDisabled \
           || { kubectl get nodes --no-headers | awk '{print $1, $2}'; exit 1; } ;;
  replaced) n=$(aws ssm get-parameter --name "/opslab/injections/${LAB:-scale-3}/drained" --query Parameter.Value --output text 2>/dev/null)
            [ -n "$n" ] && ! kubectl get node "$n" >/dev/null 2>&1 || { echo "드레인 대상 노드 $n 이 아직 클러스터에 있습니다"; exit 1; } ;;
  db) [ "$(kubectl -n "$APP_NS" get pod postgres-0 -o jsonpath='{.status.phase}' 2>/dev/null)" = Running ] && [ "$(pg_marker)" = scale-baseline ] \
        && [ -z "$(kubectl -n "$APP_NS" get sts postgres -o jsonpath='{.spec.template.spec.nodeSelector}')" ] || { echo "postgres $(kubectl -n "$APP_NS" get pod postgres-0 --no-headers 2>/dev/null) 마커 '$(pg_marker)'"; exit 1; } ;;
  *) sed -n '2,9p' "$0"; exit 2 ;;
esac
