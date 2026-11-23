#!/bin/bash
# scale-3 drain — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: 관리형 노드 그룹 노드 1대 cordon·드레인 시도, 캐시 작업 파드(opslab-cache-worker — emptyDir 사용)
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 2)
# 교체 대상: 샘플 앱 파드가 있는 관리형 노드 그룹 노드(Karpenter 노드 제외)
X=$(kubectl -n "$APP_NS" get pods -l "$SEL_APP" -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort | uniq -c | sort -rn | awk '{print $2}' \
    | while read -r n; do [ "$(kubectl get node "$n" -o jsonpath='{.metadata.labels.opslab/pool}')" = default ] && echo "$n" && break; done)
[ -n "$X" ] || X=$(kubectl get nodes -l opslab/pool=default -o name | head -1 | cut -d/ -f2)
save drained "$X"
kubectl apply -f - >/dev/null <<YAML
apiVersion: apps/v1
kind: Deployment
metadata: { name: opslab-cache-worker, namespace: $APP_NS, labels: { app.kubernetes.io/name: opslab-cache-worker, course: opslab } }
spec:
  replicas: 1
  selector: { matchLabels: { app.kubernetes.io/name: opslab-cache-worker } }
  template:
    metadata: { labels: { app.kubernetes.io/name: opslab-cache-worker, course: opslab } }
    spec:
      terminationGracePeriodSeconds: 5
      affinity: { nodeAffinity: { preferredDuringSchedulingIgnoredDuringExecution: [ { weight: 100, preference: { matchExpressions: [ { key: kubernetes.io/hostname, operator: In, values: [$X] } ] } } ] } }
      containers:
        - name: worker
          image: $(img busybox)
          command: ["sh", "-c", "while true; do date >> /cache/work.log; sleep 30; done"]
          volumeMounts: [ { name: cache, mountPath: /cache } ]
          resources: { requests: { cpu: 10m, memory: 16Mi } }
      volumes: [ { name: cache, emptyDir: {} } ]   # 노드 로컬 임시 디스크 — 파드가 다른 노드로 가면 사라진다
YAML
kubectl -n "$APP_NS" rollout status deploy opslab-cache-worker --timeout=180s >/dev/null
mkdir -p ~/opslab-work/scale; LOG=~/opslab-work/scale/drain-"$X".log
{ echo "# 노드 그룹 교체 작업 기록 — 대상 노드 $X ($(TZ=Asia/Seoul date '+%F %T'))"; echo "\$ kubectl cordon $X"; kubectl cordon "$X" 2>&1
  case $V in
    1) echo "\$ kubectl drain $X --ignore-daemonsets --timeout=60s"; kubectl drain "$X" --ignore-daemonsets --timeout=60s 2>&1 ;;
    2) echo "\$ kubectl drain $X --delete-emptydir-data --timeout=60s"; kubectl drain "$X" --delete-emptydir-data --timeout=60s 2>&1 ;;
  esac
  echo "# 작업자: 드레인이 실패해 교체(인스턴스 종료)를 진행하지 못함. 노드는 cordon 상태로 남음"; } > "$LOG" 2>&1 || true
record $V
