#!/bin/bash
# 2단계(정상 상태 정의) 판정 — 실행: bash ~/opslab/modules/heal/baseline/verify.sh
source "$(dirname "$(readlink -f "$0")")/../verify.sh"
mkdir -p ~/opslab-work/heal
OUT=$(verify_main "heal baseline(정상 상태 정의)"); RC=$?
echo "$OUT"
if [ $RC -eq 0 ]; then
  { echo "# heal 정상 상태 기준값 — $(TZ=Asia/Seoul date '+%F %T')"; echo "$OUT" | grep PASS
    echo "## 노드·AZ"; kubectl get nodes -L topology.kubernetes.io/zone --no-headers | awk '{print $1, $2, $NF}'
    echo "## 앱 파드 위치"; kubectl -n app get pods -l app.kubernetes.io/instance=opslab-app -o wide --no-headers | awk '{print $1, $3, $7}'
    echo "## PDB"; kubectl -n app get pdb opslab-app --no-headers
    echo "## 최근 분석"; kubectl -n app get analysisrun --sort-by=.metadata.creationTimestamp --no-headers | tail -3
  } > ~/opslab-work/heal/baseline.txt
  echo "기준값을 ~/opslab-work/heal/baseline.txt 에 기록했습니다."
fi
exit $RC
