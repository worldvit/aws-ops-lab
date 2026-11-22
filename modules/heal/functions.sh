#!/bin/bash
# heal 모듈(자가 복구와 무중단 운영) 함수 — full.sh(따라잡기)·장애 스크립트(lib.sh)·verify·check 가 함께 쓴다.
# 미리 common/eks.sh 를 source 해 두어야 한다. gitops 함수(Argo CD 앱 읽기·GitHub API)와 노드 명령(on_node)도 불러온다.
source "$EKS_ROOT/modules/gitops/functions.sh"
source "$EKS_ROOT/modules/cluster/node.sh"
HM="$EKS_ROOT/modules/heal"
NG="$SID-cluster-ng"                       # 관리형 노드 그룹(K1 층)
ROLL_ROLE="$SID-heal-rollouts-role"        # Argo Rollouts 컨트롤러가 CloudWatch 지표를 읽을 IRSA 역할
PV=gitops/envs/prod/values.yaml            # 운영 값 — 구축·장애가 이 파일을 커밋으로 바꾼다
BOUNDARY=arn:aws:iam::$ACCT:policy/opslab-student-boundary
HTAGS="Key=Course,Value=opslab Key=Module,Value=heal Key=Owner,Value=$SID"

# ── 1) 노드 3대(AZ 마다 하나) + 노드 자동 복구(감지는 노드 모니터링 에이전트, 교체는 관리형 노드 그룹)
#    교체 범위를 묶는다: 노드 절반 넘게 아프면 멈춤(문제가 노드가 아니라 공통 원인일 수 있으므로), 한 번에 1대씩
REPAIR_JSON='{"enabled":true,"maxUnhealthyNodeThresholdPercentage":50,"maxParallelNodesRepairedCount":1}'
ng_json() { aws eks describe-nodegroup --cluster-name "$CLUSTER" --nodegroup-name "$NG" --query nodegroup --output json 2>/dev/null; }
ng_wait() { aws eks wait nodegroup-active --cluster-name "$CLUSTER" --nodegroup-name "$NG" 2>/dev/null; }
ng_scale3() {
  [ "$(ng_json | jq -r .scalingConfig.desiredSize)" -ge 3 ] && return 0
  aws eks update-nodegroup-config --cluster-name "$CLUSTER" --nodegroup-name "$NG" --scaling-config minSize=3,maxSize=4,desiredSize=3 >/dev/null && ng_wait
}
repair_on() {
  [ "$(ng_json | jq -c '.nodeRepairConfig | {enabled,maxUnhealthyNodeThresholdPercentage,maxParallelNodesRepairedCount}')" = "$(jq -c . <<<"$REPAIR_JSON")" ] && return 0
  ng_wait; aws eks update-nodegroup-config --cluster-name "$CLUSTER" --nodegroup-name "$NG" --node-repair-config "$REPAIR_JSON" >/dev/null && ng_wait
}
nodes_ready() { kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l; }
zones_of_app() { kubectl -n "$APP_NS" get pods -l app.kubernetes.io/name=opslab-app,app.kubernetes.io/instance=opslab-app --field-selector=status.phase=Running -o json 2>/dev/null \
  | jq -r '.items[] | select((.metadata.ownerReferences[0].kind // "")!="Job") | .spec.nodeName' | sort -u \
  | while read -r n; do kubectl get node "$n" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}{"\n"}'; done | sort -u; }

# ── 2) Argo Rollouts — 미러 이미지·고정 차트, 컨트롤러는 IRSA 로 CloudWatch 를 읽는다
rollouts_role() {
  local iss; iss=$(aws eks describe-cluster --name "$CLUSTER" --query cluster.identity.oidc.issuer --output text | sed 's#^https://##')
  sed -e "s/__ACCT__/$ACCT/g" -e "s#__ISSUER__#$iss#g" -e "s/__NS__/argo-rollouts/g" -e "s/__SA__/argo-rollouts/g" "$EKS_ROOT/modules/access/irsa-trust.json" > /tmp/trust-roll.json
  aws iam get-role --role-name "$ROLL_ROLE" >/dev/null 2>&1 \
    && aws iam update-assume-role-policy --role-name "$ROLL_ROLE" --policy-document file:///tmp/trust-roll.json \
    || aws iam create-role --role-name "$ROLL_ROLE" --assume-role-policy-document file:///tmp/trust-roll.json --permissions-boundary "$BOUNDARY" --tags $HTAGS >/dev/null || return 1
  aws iam put-role-policy --role-name "$ROLL_ROLE" --policy-name cloudwatch-read --policy-document \
    '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["cloudwatch:GetMetricData","cloudwatch:ListMetrics","cloudwatch:GetMetricStatistics"],"Resource":"*"}]}'
}
rollouts_install() {
  kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl label namespace argo-rollouts course=opslab --overwrite >/dev/null
  helm upgrade --install argo-rollouts "$EKS_ROOT/vendor/charts/argo-rollouts" -n argo-rollouts --wait --timeout 10m -f "$HM/rollouts-values.yaml" \
    --set controller.image.registry="$(img_repo argo-rollouts | cut -d/ -f1)" --set controller.image.repository="$(img_repo argo-rollouts | cut -d/ -f2-)" \
    --set controller.image.tag="$(img_tag argo-rollouts)" \
    --set-string "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:aws:iam::$ACCT:role/$ROLL_ROLE" >/dev/null
}

# ── 3) 운영 값 커밋(구축 3) · 상태 읽기
values_commit() {  # 운영 값 파일을 heal 설계로 바꾸는 커밋
  local R B; R=$(fork_repo); B=$(fork_branch)
  gh_get "$R" "$B" "$PV" | grep -q '^rollout:' && return 0
  gh_put "$R" "$B" "$PV" "운영 값: probe 재설계·PDB·AZ 분산·카나리 배포" < "$HM/prod-values.yaml"
}
ro_json() { kubectl -n "$APP_NS" get rollout opslab-app -o json 2>/dev/null; }
ro_line() { ro_json | jq -r '"\(.status.phase // "-") step=\(.status.currentStepIndex // "-") stable=\(.status.stableRS // "-") canary=\(.status.currentPodHash // "-") \(.status.message // "")"'; }
ro_wait() {  # [$1=초] — Rollout 이 Healthy(카나리 끝, 새 버전이 stable)이 되고 Argo CD 앱이 모두 Synced·Healthy 일 때까지
  local i; for i in $(seq 1 $(( ${1:-600} / 10 ))); do
    [ "$(ro_json | jq -r '.status.phase')" = Healthy ] && [ "$(ro_json | jq -r '.status.stableRS == .status.currentPodHash')" = true ] && apps_wait 10 && return 0
    [ $((i % 3)) -eq 0 ] && app_refresh $APPS; sleep 10; done; return 1
}
pod_env() { ro_json | jq -r --arg k "$1" '.spec.template.spec.containers[] | select(.name=="app") | .env[]? | select(.name==$k) | .value'; }
probe_path() { ro_json | jq -r --arg p "$1" '.spec.template.spec.containers[] | select(.name=="app") | .[$p].httpGet.path // ""'; }
pdb_json() { kubectl -n "$APP_NS" get pdb opslab-app -o json 2>/dev/null; }
