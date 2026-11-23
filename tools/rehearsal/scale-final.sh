#!/bin/bash
# 강사 리허설: scale 모듈 처음부터 끝까지(정리 → 환경 → 구축 → 기준 → scale-6 → scale-4 → 정리) 시간 측정
source ~/opslab/common/eks.sh
t(){ date +%s; }
el(){ echo "== TIME $1: $(( ($(t)-$2)/60 ))분 $(( ($(t)-$2)%60 ))초"; }
echo "== cleanup"; bash common/cleanup.sh >/tmp/c1.log 2>&1 <<<"$SID"; tail -3 /tmp/c1.log
T=$(t); bash common/start.sh scale 2>&1 | tail -5; el start $T
kube_login >/dev/null
T=$(t); bash modules/scale/full.sh 2>&1 | tail -15; el build $T
for s in env hpa ca karpenter snapshot; do bash common/check.sh scale $s | tail -1; done
bash common/load.sh pod alb >/dev/null 2>&1; sleep 90
bash modules/scale/baseline/verify.sh | tail -4
source modules/scale/functions.sh
echo "== scale-6"; T=$(t); idle start; for i in $(seq 1 30); do [ "$(kp_nodes_n)" -ge 1 ] && break; sleep 20; done; echo "Karpenter 노드 $(kp_nodes_n)"
kubectl get nodes -L node.kubernetes.io/instance-type,karpenter.sh/nodepool
kubectl -n app set resources deploy opslab-idle --requests=cpu=100m,memory=128Mi
for i in $(seq 1 30); do [ "$(kp_nodes_n)" -le 0 ] && break; sleep 20; done; echo "Karpenter 노드 $(kp_nodes_n)"
mkdir -p ~/opslab-work/scale; echo "# 런북 scale-6" > ~/opslab-work/scale/runbook-scale-6.md
bash common/check.sh scale cost; idle stop; el cost $T
echo "== scale-4"; T=$(t); bash modules/scale/upgrade-steps.sh; el upgrade $T
echo "# 런북 scale-4" > ~/opslab-work/scale/runbook-scale-4.md
bash common/check.sh scale upgrade
sleep 60; bash modules/scale/baseline/verify.sh | tail -6
kubectl -n app logs deploy/opslab-load --since=60m | awk '{for(i=1;i<=NF;i++) if($i ~ /^5xx=/){split($i,a,"=");s+=a[2]}} END{print "업그레이드 동안 5xx 합계", s}'
echo "== final cleanup"; T=$(t); bash common/cleanup.sh 2>&1 <<<"$SID" | tail -8; el cleanup $T
bash common/cleanup.sh check 2>&1 | tail -15
