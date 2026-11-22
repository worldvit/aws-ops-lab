#!/bin/bash
# scale 따라잡기(start.sh scale full)와 시험(tools/test-module.sh scale)이 쓰는 1단계 구축 명령 모음 — 따라하기 페이지의 순서와 같다.
#   구축 1 HPA 튜닝 → 구축 2 클러스터 오토스케일러(실습 후 제거) → 구축 3 Karpenter → 구축 4 DB 스냅샷
set -uo pipefail
source "$(dirname "$(readlink -f "$0")")/../../common/eks.sh"
source ~/opslab-env.sh
source "$EKS_ROOT/modules/scale/functions.sh"
kube_login

echo "== 구축 1: HPA — 요청(requests) 100m 기준 CPU 50% 를 넘으면 파드 2→8개"
hpa_on || { echo "❌ HPA 설정 실패"; exit 1; }
for i in $(seq 1 18); do [ "$(hpa_json | jq -r '.status.currentMetrics[0].resource.current.averageUtilization // empty')" != "" ] && break; sleep 10; done
echo "   $(hpa_line)"
spike start 3
for i in $(seq 1 30); do [ "$(hpa_json | jq -r '.status.desiredReplicas // 0')" -gt 2 ] && break; sleep 10; done
echo "   급증 중: $(hpa_line)"
spike stop

echo "== 구축 2: 클러스터 오토스케일러 — 자리가 없으면 노드 그룹을 늘린다(최대 4대)"
ca_install || { echo "❌ 클러스터 오토스케일러 설치 실패"; exit 1; }
batch start 3 1
for i in $(seq 1 60); do [ "$(ng_json | jq -r .scalingConfig.desiredSize)" -ge 4 ] && [ "$(batch_ready)" = 2/3 ] && break; sleep 10; done
echo "   배치 $(batch_ready) Running, 노드 $(nodes_ready)대 (노드 그룹 원하는 수 $(ng_json | jq -r .scalingConfig.desiredSize) = 최대) — 남은 1개는 최대 크기 때문에 Pending"
batch stop

echo "== 구축 3: 클러스터 오토스케일러 제거 → Karpenter(NodePool·EC2NodeClass)"
ca_remove
ng_size 2 4 2 || true
kp_install || { echo "❌ Karpenter 설치 실패"; exit 1; }
kp_nodes
for i in $(seq 1 30); do kp_ready && break; sleep 10; done
kp_ready || { echo "❌ NodePool·EC2NodeClass 가 Ready 가 아닙니다"; kubectl get nodepool,ec2nodeclass; exit 1; }
batch start 3 1
for i in $(seq 1 60); do [ "$(batch_ready)" = 3/3 ] && break; sleep 10; done
echo "   배치 $(batch_ready) Running, Karpenter 노드 $(kp_nodes_n)대: $(kubectl get nodes -l karpenter.sh/nodepool -L node.kubernetes.io/instance-type --no-headers | awk '{print $NF}' | tr '\n' ' ')"
batch stop
for i in $(seq 1 30); do [ "$(kp_nodes_n)" -eq 0 ] && break; sleep 10; done
echo "   배치 정지 뒤 Karpenter 노드 $(kp_nodes_n)대(빈 노드 정리)"

echo "== 구축 4: DB 스냅샷 — 기준 데이터(마커)를 넣고 PostgreSQL 디스크를 스냅샷으로"
snap_make || { echo "❌ 스냅샷 실패"; kubectl -n "$APP_NS" describe volumesnapshot pg-baseline | tail -8; exit 1; }
echo "   스냅샷 pg-baseline readyToUse=$(snap_ready), 마커 $(pg_marker)"
echo "✅ scale 구축 완료"
