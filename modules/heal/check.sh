# heal 구축 확인 지점 — common/check.sh 가 source 한다. 단계 이름은 따라하기 페이지의 확인 지점과 같다.
STAGES="env nodes rollouts values canary load"
_hm() { [ -n "${HM:-}" ] || source "$EKS_ROOT/modules/heal/functions.sh"; export GH_T=${GH_T:-$(gh_token)}; }
stage_env() {       # 사전 조건: K5 층(Argo CD·App of Apps)·오늘 브랜치
  kube_login && kubectl get ns default >/dev/null 2>&1 && ok "kubectl 접속(kubeconfig)" || { ng "kubectl 로 접속되지 않습니다" "bash ~/opslab/common/start.sh heal"; return; }
  _hm; local a
  for a in $APPS; do [[ "$(app_line $a)" == "Synced Healthy "* ]] && ok "Argo CD 앱 $a Synced·Healthy" || ng "$a: $(app_line $a)" "bash ~/opslab/common/start.sh heal (다시 실행하면 이어서 합니다)"; done
  [ -n "${GITOPS_BRANCH:-}" ] && ok "오늘 브랜치: $GITOPS_BRANCH" || ng "오늘 브랜치가 없습니다" "bash ~/opslab/common/fork.sh prepare heal && source ~/opslab-env.sh"
  command -v kubectl-argo-rollouts >/dev/null && ok "kubectl argo rollouts 플러그인" || ng "플러그인이 없습니다" "bash ~/opslab/common/tools.sh && source ~/.bashrc"
}
stage_nodes() {     # 구축 1: 노드 3대·자동 복구
  _hm
  [ "$(nodes_ready)" -ge 3 ] && ok "노드 $(nodes_ready)대 Ready" || ng "노드가 3대가 아닙니다 ($(nodes_ready)대)" "구축 1 — aws eks update-nodegroup-config … --scaling-config minSize=3,maxSize=4,desiredSize=3"
  [ "$(kubectl get nodes -L topology.kubernetes.io/zone --no-headers | awk '{print $NF}' | sort -u | wc -l)" -ge 3 ] && ok "노드가 AZ 3곳에 하나씩" || ng "노드 AZ 가 3곳이 아닙니다" "구축 1 — 몇 분 뒤 다시 확인(노드 그룹이 AZ 를 고르게 채움)"
  bash "$EKS_ROOT/modules/heal/state.sh" repair >/dev/null && ok "노드 자동 복구: 켜짐·절반 넘으면 멈춤·한 번에 1대" || ng "노드 자동 복구 설정이 기준과 다릅니다" "구축 1 — aws eks update-nodegroup-config … --node-repair-config '$REPAIR_JSON'"
}
stage_rollouts() {  # 구축 2: Argo Rollouts
  _hm
  kubectl -n argo-rollouts get deploy argo-rollouts >/dev/null 2>&1 && [ "$(kubectl -n argo-rollouts get deploy argo-rollouts -o jsonpath='{.status.readyReplicas}')" = 1 ] \
    && ok "Argo Rollouts 컨트롤러 Running" || ng "Argo Rollouts 가 없습니다" "구축 2 — helm upgrade --install argo-rollouts …"
  kubectl -n argo-rollouts get sa argo-rollouts -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null | grep -q "$ROLL_ROLE" \
    && ok "컨트롤러 서비스 계정에 IRSA 역할($ROLL_ROLE)" || ng "IRSA 어노테이션이 없습니다" "구축 2 — --set-string serviceAccount.annotations…"
}
stage_values() {    # 구축 3: 운영 값 커밋 → Rollout
  _hm
  ro_json >/dev/null && ok "Deployment 대신 Rollout(opslab-app)" || { ng "Rollout 이 없습니다" "구축 3 — ~/fork 에서 운영 값을 바꿔 커밋·푸시"; return; }
  bash "$EKS_ROOT/modules/heal/state.sh" probes >/dev/null && ok "probe 역할 구분(startup·/health·/ready)" || ng "probe 설정이 기준과 다릅니다" "구축 3 — prod-values.yaml 과 비교(diff)"
  bash "$EKS_ROOT/modules/heal/state.sh" pdb >/dev/null && ok "PDB(최소 1개 유지)" || ng "PDB 가 없거나 드레인을 막습니다" "구축 3"
  bash "$EKS_ROOT/modules/heal/state.sh" spread >/dev/null && ok "AZ 분산 — 파드가 AZ 2곳 이상" || ng "AZ 분산이 안 됩니다" "구축 3 — 몇 분 뒤 다시(롤아웃 중일 수 있음)"
}
stage_canary() {    # 구축 4: 카나리 연습
  _hm
  [ "$(pod_env APP_VERSION)" = v2 ] && ok "운영 값 APP_VERSION v2 커밋" || ng "v2 커밋이 없습니다" "구축 4"
  bash "$EKS_ROOT/modules/heal/state.sh" rollout >/dev/null && ok "Rollout Healthy — v2 가 stable" || ng "카나리가 아직 진행 중이거나 멈췄습니다: $(ro_line)" "구축 4 — kubectl argo rollouts get rollout opslab-app -n app --watch"
  [ "$(kubectl -n app get analysisrun --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].status.phase}' 2>/dev/null)" = Successful ] && ok "분석(AnalysisRun) 성공" || ng "분석 결과가 성공이 아닙니다" "구축 4 — kubectl -n app describe analysisrun"
}
stage_load() {      # 2단계(정상 상태 정의)
  kubectl -n app get deploy opslab-load -o jsonpath='{.spec.template.spec.containers[0].env[0].value}' 2>/dev/null | grep -q elb.amazonaws.com \
    && ok "부하 파드가 ALB 로 요청 중" || ng "부하 파드가 없거나 ALB 로 보내지 않습니다" "bash ~/opslab/common/load.sh pod alb"
  [ -f ~/opslab-work/heal/baseline.txt ] && ok "정상 상태 기준값 기록됨" || ng "기준값 기록 없음" "2단계 — bash ~/opslab/modules/heal/baseline/verify.sh"
}
