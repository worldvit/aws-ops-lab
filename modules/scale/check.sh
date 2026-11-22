# scale 구축 확인 지점 — common/check.sh 가 source 한다. 단계 이름은 따라하기 페이지의 확인 지점과 같다.
STAGES="env hpa ca karpenter snapshot load upgrade cost"
_sm() { [ -n "${SM:-}" ] || source "$EKS_ROOT/modules/scale/functions.sh"; }
stage_env() {       # 사전 조건: K3 층(샘플 앱·DB·ALB), 클러스터 버전
  kube_login && kubectl get ns default >/dev/null 2>&1 && ok "kubectl 접속(kubeconfig)" || { ng "kubectl 로 접속되지 않습니다" "bash ~/opslab/common/start.sh scale"; return; }
  _sm
  local v; v=$(aws eks describe-cluster --name "$CLUSTER" --query cluster.version --output text 2>/dev/null)
  [ "$v" = "$(cval eks_version_prev)" ] || [ "$v" = "$(cval eks_version)" ] && ok "클러스터 버전 $v" || ng "클러스터 버전 $v" "bash ~/opslab/common/start.sh scale"
  [ "$(kubectl -n app get deploy opslab-app -o jsonpath='{.status.availableReplicas}' 2>/dev/null)" -ge 2 ] 2>/dev/null && ok "샘플 앱 Available" || ng "샘플 앱이 없습니다" "bash ~/opslab/common/start.sh scale"
  kubectl -n app get ingress opslab-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null | grep -q elb && ok "Ingress(ALB) 주소" || ng "Ingress(ALB) 가 없습니다" "bash ~/opslab/common/start.sh scale"
  [ "$(nodes_ready)" -ge 2 ] && ok "노드 $(nodes_ready)대 Ready" || ng "노드가 2대 미만입니다" "bash ~/opslab/common/start.sh scale"
}
stage_hpa() {       # 구축 1: HPA
  _sm
  hpa_json >/dev/null && ok "HPA opslab-app 있음 ($(hpa_line))" || { ng "HPA 가 없습니다" "구축 1 — helm upgrade … --set hpa.enabled=true"; return; }
  bash "$EKS_ROOT/modules/scale/state.sh" hpa >/dev/null && ok "HPA 가 CPU 사용률을 읽고 있음, 최소 2 < 최대 8" || ng "HPA 가 기준과 다르거나 아직 지표가 없습니다" "구축 1 — 1분 뒤 kubectl -n app get hpa"
}
stage_ca() {        # 구축 2: 클러스터 오토스케일러(실습 후 구축 3에서 제거)
  _sm
  if kubectl get crd nodepools.karpenter.sh >/dev/null 2>&1; then ok "구축 3 으로 넘어감(클러스터 오토스케일러는 제거 대상)"; return; fi
  [ "$(kubectl -n kube-system get deploy -l app.kubernetes.io/name=aws-cluster-autoscaler -o jsonpath='{.items[0].status.readyReplicas}' 2>/dev/null)" = 1 ] \
    && ok "클러스터 오토스케일러 Running" || ng "클러스터 오토스케일러가 없습니다" "구축 2 — helm upgrade --install cluster-autoscaler …"
  aws autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[?Tags[?Key=='k8s.io/cluster-autoscaler/$CLUSTER']].AutoScalingGroupName" --output text | grep -q . \
    && ok "노드 그룹 오토스케일링 그룹에 자동 발견 태그" || ng "자동 발견 태그가 붙은 오토스케일링 그룹이 없습니다" "구축 2"
}
stage_karpenter() { # 구축 3: Karpenter
  _sm
  helm -n kube-system status cluster-autoscaler >/dev/null 2>&1 && ng "클러스터 오토스케일러가 아직 있습니다 — Karpenter 와 노드를 두고 다툽니다" "구축 3 — helm -n kube-system uninstall cluster-autoscaler" || ok "클러스터 오토스케일러 제거됨"
  bash "$EKS_ROOT/modules/scale/state.sh" karpenter >/dev/null && ok "Karpenter 컨트롤러·NodePool·EC2NodeClass Ready" || ng "Karpenter 가 기준 상태가 아닙니다" "구축 3 — kubectl get nodepool,ec2nodeclass"
  kubectl -n kube-system get sa karpenter -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null | grep -q "$KP_ROLE" \
    && ok "컨트롤러 서비스 계정에 IRSA 역할($KP_ROLE)" || ng "IRSA 어노테이션이 없습니다" "구축 3 — kp_install"
}
stage_snapshot() {  # 구축 4: DB 스냅샷
  _sm
  [ "$(pg_marker)" = scale-baseline ] && ok "기준 데이터(opslab_marker) 있음" || ng "기준 데이터가 없습니다" "구축 4 — insert into opslab_marker …"
  [ "$(snap_ready)" = true ] && ok "스냅샷 pg-baseline readyToUse" || ng "스냅샷이 없거나 준비 중입니다" "구축 4 — 1~2분 뒤 kubectl -n app get volumesnapshot"
}
stage_load() {      # 2단계(정상 상태 정의)
  kubectl -n app get deploy opslab-load -o jsonpath='{.spec.template.spec.containers[0].env[0].value}' 2>/dev/null | grep -q elb.amazonaws.com \
    && ok "부하 파드가 ALB 로 요청 중" || ng "부하 파드가 없거나 ALB 로 보내지 않습니다" "bash ~/opslab/common/load.sh pod alb"
  [ -f ~/opslab-work/scale/baseline.txt ] && ok "정상 상태 기준값 기록됨" || ng "기준값 기록 없음" "2단계 — bash ~/opslab/modules/scale/baseline/verify.sh"
}
stage_upgrade() {   # 운영 Lab scale-4: 클러스터 버전 업그레이드
  _sm
  local want v ng_v bad a
  want=$(cval eks_version); v=$(aws eks describe-cluster --name "$CLUSTER" --query cluster.version --output text)
  [ "$v" = "$want" ] && ok "컨트롤 플레인 $v" || ng "컨트롤 플레인 $v (목표 $want)" "scale-4 2 — aws eks update-cluster-version"
  bad=""; for a in vpc-cni kube-proxy coredns aws-ebs-csi-driver metrics-server; do
    d=$(aws eks describe-addon-versions --addon-name "$a" --kubernetes-version "$v" --query 'addons[0].addonVersions[?compatibilities[0].defaultVersion==`true`].addonVersion | [0]' --output text 2>/dev/null)
    c=$(aws eks describe-addon --cluster-name "$CLUSTER" --addon-name "$a" --query addon.addonVersion --output text 2>/dev/null)
    [ "$c" = "$d" ] || bad="$bad $a($c→$d)"; done
  [ -z "$bad" ] && ok "애드온이 $v 기본 버전" || ng "기본 버전이 아닌 애드온:$bad" "scale-4 3 — aws eks update-addon"
  ng_v=$(ng_json | jq -r .version)
  [ "$ng_v" = "$want" ] && ok "관리형 노드 그룹 $ng_v" || ng "관리형 노드 그룹 $ng_v (목표 $want)" "scale-4 4 — aws eks update-nodegroup-version"
  [ "$(kubectl get nodes --no-headers | awk '{print $5}' | cut -d. -f1-2 | sort -u | tr -d v)" = "$want" ] && ok "모든 노드 kubelet $want" || ng "kubelet 버전이 섞여 있습니다: $(kubectl get nodes --no-headers | awk '{print $5}' | sort -u | tr '\n' ' ')" "scale-4 4 — Karpenter 노드는 드리프트로 몇 분 뒤 교체"
  [ -f ~/opslab-work/scale/runbook-scale-4.md ] && ok "업그레이드 런북 기록" || ng "런북이 없습니다" "scale-4 5 — ~/opslab-work/scale/runbook-scale-4.md"
}
stage_cost() {      # 운영 Lab scale-6: 유휴 용량 정리
  _sm
  local over
  over=$(kubectl -n app get deploy opslab-idle -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null)
  [ -z "$over" ] || [ "$over" = 100m ] && ok "과대 요청 Deployment(opslab-idle) 정리됨(요청 ${over:-삭제})" || ng "opslab-idle 의 CPU 요청이 아직 $over 입니다" "scale-6 3 — 요청을 실제 사용량에 맞춰 줄이기"
  [ "$(kp_nodes_n)" -le 1 ] && ok "Karpenter 노드 $(kp_nodes_n)대 — 통합(consolidation)으로 유휴 노드 정리" || ng "Karpenter 노드가 $(kp_nodes_n)대 남아 있습니다" "scale-6 4 — 1~2분 뒤 다시(consolidateAfter 1m)"
  [ -f ~/opslab-work/scale/runbook-scale-6.md ] && ok "비용 정리 런북 기록" || ng "런북이 없습니다" "scale-6 5 — ~/opslab-work/scale/runbook-scale-6.md"
}
