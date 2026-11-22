#!/bin/bash
# 2단계(정상 상태 정의) 판정 — 실행: bash ~/opslab/modules/scale/baseline/verify.sh
source "$(dirname "$(readlink -f "$0")")/../verify.sh"
mkdir -p ~/opslab-work/scale
OUT=$(verify_main "scale baseline(정상 상태 정의)"); RC=$?
echo "$OUT"
if [ $RC -eq 0 ]; then
  { echo "# scale 정상 상태 기준값 — $(TZ=Asia/Seoul date '+%F %T')"; echo "$OUT" | grep PASS
    echo "## 노드"; kubectl get nodes -L node.kubernetes.io/instance-type,topology.kubernetes.io/zone,karpenter.sh/nodepool --no-headers
    echo "## HPA"; kubectl -n app get hpa opslab-app --no-headers
    echo "## 노드 자원 요청 합계"; kubectl describe nodes | grep -A6 "Allocated resources" | grep -E "cpu|memory"
  } > ~/opslab-work/scale/baseline.txt
  echo "기준값을 ~/opslab-work/scale/baseline.txt 에 기록했습니다."
fi
exit $RC
