#!/bin/bash
# scale 모듈(스케일 · 업그레이드 · 비용) 함수 — full.sh(따라잡기)·장애 스크립트(lib.sh)·verify·check·cleanup 이 함께 쓴다.
# 미리 common/eks.sh 를 source 해 두어야 한다.
SM="$EKS_ROOT/modules/scale"
ACCT=${ACCT:-$(aws sts get-caller-identity --query Account --output text)}
NG="$SID-cluster-ng"                          # 관리형 노드 그룹(K1 층) — 클러스터 오토스케일러가 늘리고 줄인다
NODE_ROLE="$SID-cluster-node-role"            # K1 층 노드 역할 — Karpenter 노드도 같은 역할을 쓴다(접근 항목이 이미 있다)
CA_ROLE="$SID-scale-ca-role"                  # 클러스터 오토스케일러 IRSA 역할(오토스케일링 그룹 크기 조정)
KP_ROLE="$SID-scale-karpenter-role"           # Karpenter 컨트롤러 IRSA 역할(EC2 직접 생성·삭제)
BOUNDARY=arn:aws:iam::$ACCT:policy/opslab-student-boundary
HTAGS="Key=Course,Value=opslab Key=Module,Value=scale Key=Owner,Value=$SID"
SEL_APP="app.kubernetes.io/instance=opslab-app"

ng_json() { aws eks describe-nodegroup --cluster-name "$CLUSTER" --nodegroup-name "$NG" --query nodegroup --output json 2>/dev/null; }
ng_wait() { aws eks wait nodegroup-active --cluster-name "$CLUSTER" --nodegroup-name "$NG" 2>/dev/null; }
ng_size() {  # $1=min $2=max $3=desired — 노드 그룹 크기(이미 같으면 그대로)
  [ "$(ng_json | jq -c '.scalingConfig|[.minSize,.maxSize,.desiredSize]')" = "[$1,$2,$3]" ] && return 0
  ng_wait; aws eks update-nodegroup-config --cluster-name "$CLUSTER" --nodegroup-name "$NG" --scaling-config "minSize=$1,maxSize=$2,desiredSize=$3" >/dev/null && ng_wait
}
nodes_ready() { kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l; }
nodes_settled() {  # 막 들어오는 노드(3분 미만)를 뺀 노드 목록 — "이름 상태" (Karpenter·오토스케일러가 새 노드를 붙이는 중이면 잠깐 NotReady 다)
  kubectl get nodes -o json 2>/dev/null | jq -r --argjson now "$(date +%s)" '.items[] | select(($now - (.metadata.creationTimestamp|fromdate)) > 180) | select(.metadata.deletionTimestamp==null)
    | "\(.metadata.name) \([.status.conditions[]|select(.type=="Ready")|.status][0]) \(.spec.unschedulable // false)"'; }
pending_pods() {  # Pending 파드(막 들어오는 노드에 붙는 DaemonSet 파드는 뺀다)
  kubectl get pods -A --field-selector=status.phase=Pending -o json 2>/dev/null | jq -r '.items[] | select(.metadata.deletionTimestamp==null)
    | select((.metadata.ownerReferences[0].kind // "")!="DaemonSet") | "\(.metadata.namespace)/\(.metadata.name)"'; }
irsa_role() {  # $1=역할 이름 $2=네임스페이스 $3=서비스 계정 $4=정책 파일
  local iss; iss=$(aws eks describe-cluster --name "$CLUSTER" --query cluster.identity.oidc.issuer --output text | sed 's#^https://##')
  sed -e "s/__ACCT__/$ACCT/g" -e "s#__ISSUER__#$iss#g" -e "s/__NS__/$2/g" -e "s/__SA__/$3/g" "$EKS_ROOT/modules/access/irsa-trust.json" > "/tmp/trust-$1.json"
  aws iam get-role --role-name "$1" >/dev/null 2>&1 \
    && aws iam update-assume-role-policy --role-name "$1" --policy-document "file:///tmp/trust-$1.json" \
    || aws iam create-role --role-name "$1" --assume-role-policy-document "file:///tmp/trust-$1.json" --permissions-boundary "$BOUNDARY" --tags $HTAGS >/dev/null || return 1
  sed -e "s/__ACCT__/$ACCT/g" -e "s/__REGION__/$AWS_REGION/g" -e "s/__CLUSTER__/$CLUSTER/g" -e "s/__NODE_ROLE__/$NODE_ROLE/g" "$4" > "/tmp/policy-$1.json"
  aws iam put-role-policy --role-name "$1" --policy-name scale --policy-document "file:///tmp/policy-$1.json"
}

# ── 1) HPA — 부하에 따라 파드 수를 늘린다. 기준은 "요청(requests) 대비 CPU 사용률"이다
HPA_SET=(--set hpa.enabled=true --set hpa.minReplicas=2 --set hpa.maxReplicas=8 --set hpa.cpuUtilization=50
         --set resources.requests.cpu=50m --set resources.requests.memory=128Mi --set resources.limits.cpu=500m --set resources.limits.memory=256Mi --set preStopSleep=30
         --set 'nodeSelector.opslab/pool=default')   # 앱은 관리형 노드에만 — Karpenter 가 노드를 정리(통합)할 때 앱 파드가 쫓겨나 5xx 가 나지 않게
hpa_on() {  # 파드 수가 자주 바뀌므로 ALB 준비 게이트를 켠다 — 새 파드가 ALB 에서 healthy 가 돼야 Ready, 옛 파드는 그다음에 내려간다
  kubectl label namespace "$APP_NS" elbv2.k8s.aws/pod-readiness-gate-inject=enabled --overwrite >/dev/null
  helm -n "$APP_NS" upgrade opslab-app "$EKS_ROOT/charts/opslab-app" --reuse-values "${HPA_SET[@]}" --wait --timeout 5m >/dev/null; }
hpa_json() { kubectl -n "$APP_NS" get hpa opslab-app -o json 2>/dev/null; }
hpa_line() { hpa_json | jq -r '"CPU \(.status.currentMetrics[0].resource.current.averageUtilization // "?")%/\(.spec.metrics[0].resource.target.averageUtilization)% · 파드 \(.status.currentReplicas // 0)→\(.status.desiredReplicas // 0) (최소 \(.spec.minReplicas)·최대 \(.spec.maxReplicas))"'; }
spike() {  # start [병렬 수] | stop — 샘플 앱 Service 로 쉬지 않고 요청을 보내는 "트래픽 급증" 파드(CPU 를 올린다)
  if [ "${1:-start}" = stop ]; then kubectl -n "$APP_NS" delete deploy opslab-spike --ignore-not-found --wait=false >/dev/null
    kubectl -n "$APP_NS" delete pod -l app.kubernetes.io/name=opslab-spike --grace-period=0 --force --wait=false >/dev/null 2>&1; return 0; fi
  kubectl -n "$APP_NS" wait --for=delete deploy/opslab-spike --timeout=90s >/dev/null 2>&1 || true   # 방금 멈춘 것이 아직 지워지는 중이면 apply 가 실패한다
  kubectl apply -f - >/dev/null <<YAML
apiVersion: apps/v1
kind: Deployment
metadata: { name: opslab-spike, namespace: $APP_NS, labels: { app.kubernetes.io/name: opslab-spike, course: opslab } }
spec:
  replicas: ${2:-3}
  selector: { matchLabels: { app.kubernetes.io/name: opslab-spike } }
  template:
    metadata: { labels: { app.kubernetes.io/name: opslab-spike, course: opslab } }
    spec:
      terminationGracePeriodSeconds: 1      # 멈추면 바로 끝나게(셸은 종료 신호를 무시하므로)
      containers:
        - name: spike
          image: $(img busybox)
          command: ["sh", "-c", "while true; do for i in 1 2 3 4 5 6 7 8; do wget -q -O /dev/null -T 3 http://opslab-app.$APP_NS.svc/api & done; wait; done"]
          resources: { requests: { cpu: 50m, memory: 32Mi }, limits: { cpu: 300m, memory: 64Mi } }
YAML
}

# ── 2) 클러스터 오토스케일러 — 파드가 놓일 자리가 없으면(Pending) 노드 그룹(오토스케일링 그룹)의 원하는 수를 늘린다
ca_install() {
  irsa_role "$CA_ROLE" kube-system cluster-autoscaler "$SM/ca-policy.json" || return 1
  helm upgrade --install cluster-autoscaler "$EKS_ROOT/vendor/charts/cluster-autoscaler" -n kube-system --wait --timeout 5m \
    --set autoDiscovery.clusterName="$CLUSTER" --set awsRegion="$AWS_REGION" --set cloudProvider=aws \
    --set image.repository="$(img_repo cluster-autoscaler)" --set image.tag="$(img_tag cluster-autoscaler)" \
    --set rbac.serviceAccount.name=cluster-autoscaler \
    --set-string "rbac.serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:aws:iam::$ACCT:role/$CA_ROLE" \
    --set extraArgs.scale-down-unneeded-time=2m --set extraArgs.scale-down-delay-after-add=2m --set extraArgs.skip-nodes-with-local-storage=false \
    --set extraArgs.balance-similar-node-groups=true >/dev/null
}
ca_remove() {  # Karpenter 와 같은 노드를 두고 다투지 않도록 지운다
  helm -n kube-system uninstall cluster-autoscaler >/dev/null 2>&1; aws iam delete-role-policy --role-name "$CA_ROLE" --policy-name scale >/dev/null 2>&1
  aws iam delete-role --role-name "$CA_ROLE" >/dev/null 2>&1; return 0
}
batch() {  # start [개수] [CPU] | stop — 큰 자원을 요청하는 "배치 작업" 파드(노드가 더 있어야 뜬다)
  if [ "${1:-start}" = stop ]; then kubectl -n "$APP_NS" delete deploy opslab-batch --ignore-not-found --wait=false >/dev/null; return 0; fi
  kubectl -n "$APP_NS" wait --for=delete deploy/opslab-batch --timeout=90s >/dev/null 2>&1 || true   # 방금 멈춘 것이 아직 지워지는 중이면 apply 가 실패한다
  kubectl apply -f - >/dev/null <<YAML
apiVersion: apps/v1
kind: Deployment
metadata: { name: opslab-batch, namespace: $APP_NS, labels: { app.kubernetes.io/name: opslab-batch, course: opslab } }
spec:
  replicas: ${2:-3}
  selector: { matchLabels: { app.kubernetes.io/name: opslab-batch } }
  template:
    metadata: { labels: { app.kubernetes.io/name: opslab-batch, course: opslab } }
    spec:
      terminationGracePeriodSeconds: 5
      containers:
        - name: batch
          image: $(img busybox)
          command: ["sh", "-c", "sleep 365d"]
          resources: { requests: { cpu: "${3:-1}", memory: 512Mi } }
YAML
}
batch_ready() { kubectl -n "$APP_NS" get deploy opslab-batch -o json 2>/dev/null | jq -r '"\(.status.readyReplicas // 0)/\(.spec.replicas)"'; }

# ── 3) Karpenter — 노드 그룹 없이 Pending 파드에 알맞은 EC2 를 바로 고른다. NodePool(무엇을)·EC2NodeClass(어떻게)
kp_install() {
  irsa_role "$KP_ROLE" kube-system karpenter "$SM/karpenter-policy.json" || return 1
  helm upgrade --install karpenter "$EKS_ROOT/vendor/charts/karpenter" -n kube-system --wait --timeout 10m -f "$SM/karpenter-values.yaml" \
    --set settings.clusterName="$CLUSTER" \
    --set controller.image.repository="$(img_repo karpenter)" --set controller.image.tag="$(img_tag karpenter)" --set controller.image.digest="" \
    --set-string "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:aws:iam::$ACCT:role/$KP_ROLE" >/dev/null
}
kp_nodes() {  # EC2NodeClass·NodePool(기준 상태) 적용
  sed -e "s/__SID__/$SID/g" -e "s/__CLUSTER__/$CLUSTER/g" -e "s/__NODE_ROLE__/$NODE_ROLE/g" "$SM/karpenter-nodes.yaml" | kubectl apply -f - >/dev/null
}
np_json() { kubectl get nodepool default -o json 2>/dev/null; }
nc_json() { kubectl get ec2nodeclass default -o json 2>/dev/null; }
kp_ready() { [ "$(np_json | jq -r '[.status.conditions[]?|select(.type=="Ready")][0].status')" = True ] && [ "$(nc_json | jq -r '[.status.conditions[]?|select(.type=="Ready")][0].status')" = True ]; }
kp_nodes_n() { kubectl get nodes -l karpenter.sh/nodepool --no-headers 2>/dev/null | wc -l; }
kp_cleanup() {  # NodePool → NodeClaim(노드) → EC2NodeClass → 컨트롤러 순으로 지운다(컨트롤러를 먼저 지우면 EC2 가 남는다)
  kubectl get crd nodepools.karpenter.sh >/dev/null 2>&1 || return 0
  kubectl delete nodepools.karpenter.sh --all --wait=false >/dev/null 2>&1
  local i; for i in $(seq 1 30); do [ "$(kubectl get nodeclaims.karpenter.sh --no-headers 2>/dev/null | wc -l)" -eq 0 ] && break; sleep 10; done
  kubectl delete ec2nodeclasses.karpenter.k8s.aws --all --timeout=180s >/dev/null 2>&1
}

# ── 4) DB 스냅샷 — PostgreSQL(StatefulSet + EBS)의 디스크를 스냅샷으로 떠 둔다(scale-5 복구용)
pg_sql() { kubectl -n "$APP_NS" exec postgres-0 -- psql -U app -d opslab -tAc "$1" 2>/dev/null; }
snap_make() {  # 기준 데이터(마커) 넣기 → VolumeSnapshotClass → 스냅샷
  pg_sql "create table if not exists opslab_marker(v text primary key, at timestamptz default now()); insert into opslab_marker(v) values ('scale-baseline') on conflict do nothing" >/dev/null
  sed "s/__SID__/$SID/g" "$SM/snapshot.yaml" | kubectl apply -f - >/dev/null
  local i; for i in $(seq 1 36); do [ "$(snap_ready)" = true ] && return 0; sleep 10; done; return 1
}
snap_ready() { kubectl -n "$APP_NS" get volumesnapshot pg-baseline -o jsonpath='{.status.readyToUse}' 2>/dev/null; }
pg_marker() { pg_sql "select v from opslab_marker where v='scale-baseline'"; }
pg_restore() {  # 스냅샷에서 PVC 복원 — PostgreSQL 을 멈추고, 같은 이름의 PVC 를 스냅샷에서 만들고, 다시 띄운다
  kubectl -n "$APP_NS" scale sts postgres --replicas=0 >/dev/null; kubectl -n "$APP_NS" wait --for=delete pod/postgres-0 --timeout=120s >/dev/null 2>&1
  kubectl -n "$APP_NS" delete pvc data-postgres-0 --wait=true --timeout=120s >/dev/null 2>&1
  sed "s/__SID__/$SID/g" "$SM/pvc-restore.yaml" | kubectl apply -f - >/dev/null
  kubectl -n "$APP_NS" scale sts postgres --replicas=1 >/dev/null
  kubectl -n "$APP_NS" rollout status sts postgres --timeout=300s >/dev/null
}

# ── 5) 운영 Lab scale-6 — 과대 요청(쓰지도 않는데 CPU 를 크게 잡아 둔) 서비스. Karpenter 가 이 요청 때문에 노드를 하나 더 띄운다
idle() {  # start | stop
  if [ "${1:-start}" = stop ]; then kubectl -n "$APP_NS" delete deploy opslab-idle --ignore-not-found --wait=false >/dev/null; return 0; fi
  kubectl -n "$APP_NS" wait --for=delete deploy/opslab-idle --timeout=90s >/dev/null 2>&1 || true   # 방금 멈춘 것이 아직 지워지는 중이면 apply 가 실패한다
  kubectl apply -f - >/dev/null <<YAML
apiVersion: apps/v1
kind: Deployment
metadata: { name: opslab-idle, namespace: $APP_NS, labels: { app.kubernetes.io/name: opslab-idle, course: opslab } }
spec:
  replicas: 2
  selector: { matchLabels: { app.kubernetes.io/name: opslab-idle } }
  template:
    metadata: { labels: { app.kubernetes.io/name: opslab-idle, course: opslab } }
    spec:
      terminationGracePeriodSeconds: 5
      containers:
        - name: report
          image: $(img busybox)
          command: ["sh", "-c", "while true; do sleep 3600; done"]     # 하루 한 번 보고서를 만드는 서비스(평소엔 거의 쉰다)
          resources: { requests: { cpu: 1500m, memory: 1Gi } }          # "넉넉하게" 잡아 둔 요청 — 실제 사용은 1m 안팎
YAML
}
