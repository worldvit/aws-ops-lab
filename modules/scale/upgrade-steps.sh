#!/bin/bash
# 운영 Lab scale-4 — 클러스터 버전 업그레이드 절차(따라하기 페이지와 같은 순서). 강사 시험·따라잡기용 — 수강생은 페이지의 명령을 한 단계씩 직접 실행한다.
#   사전 점검 → 컨트롤 플레인 → 애드온 → 노드(관리형 노드 그룹, Karpenter 노드는 드리프트로 자동 교체)
set -uo pipefail
source "$(dirname "$(readlink -f "$0")")/../../common/eks.sh"
source "$EKS_ROOT/modules/scale/functions.sh"
kube_login
TO=$(cval eks_version); FROM=$(aws eks describe-cluster --name "$CLUSTER" --query cluster.version --output text)
echo "== 1 사전 점검: $FROM → $TO"
aws eks list-insights --cluster-name "$CLUSTER" --filter kubernetesVersions="$TO" --query 'insights[].[name,insightStatus.status]' --output text
kubectl apply --dry-run=server -f "$SM/legacy/app-extras.yaml" 2>&1 | tail -2
sed -e 's#autoscaling/v2beta2#autoscaling/v2#; s#policy/v1beta1#policy/v1#' "$SM/legacy/app-extras.yaml" | kubectl apply --dry-run=server -f - | tail -2
[ "$FROM" = "$TO" ] || {
  echo "== 2 컨트롤 플레인"
  U=$(aws eks update-cluster-version --name "$CLUSTER" --kubernetes-version "$TO" --query update.id --output text)
  aws eks wait cluster-active --name "$CLUSTER"; for i in $(seq 1 90); do s=$(aws eks describe-update --name "$CLUSTER" --update-id "$U" --query update.status --output text); [ "$s" = InProgress ] || break; sleep 20; done
  echo "   업데이트 $s, 버전 $(aws eks describe-cluster --name "$CLUSTER" --query cluster.version --output text)"; }
echo "== 3 애드온(기본 버전으로)"
for a in vpc-cni kube-proxy coredns aws-ebs-csi-driver metrics-server snapshot-controller eks-node-monitoring-agent; do
  d=$(aws eks describe-addon-versions --addon-name "$a" --kubernetes-version "$TO" --query 'addons[0].addonVersions[?compatibilities[0].defaultVersion==`true`].addonVersion | [0]' --output text 2>/dev/null)
  c=$(aws eks describe-addon --cluster-name "$CLUSTER" --addon-name "$a" --query addon.addonVersion --output text 2>/dev/null) || continue
  [ "$c" = "$d" ] || { aws eks update-addon --cluster-name "$CLUSTER" --addon-name "$a" --addon-version "$d" --resolve-conflicts PRESERVE >/dev/null && aws eks wait addon-active --cluster-name "$CLUSTER" --addon-name "$a"; }
  echo "   $a $c → $(aws eks describe-addon --cluster-name "$CLUSTER" --addon-name "$a" --query addon.addonVersion --output text)"
done
echo "== 4 노드: 관리형 노드 그룹(한 번에 1대씩 교체 — PDB 를 지킨다)"
[ "$(ng_json | jq -r .version)" = "$TO" ] || { aws eks update-nodegroup-version --cluster-name "$CLUSTER" --nodegroup-name "$NG" >/dev/null; ng_wait; }
echo "   노드 그룹 $(ng_json | jq -r .version)"
for i in $(seq 1 30); do [ "$(kubectl get nodes --no-headers | awk '{print $5}' | cut -d. -f1-2 | sort -u | tr -d v)" = "$TO" ] && break; sleep 20; done
kubectl get nodes -L karpenter.sh/nodepool --no-headers | awk '{print $1, $2, $5, $NF}'
