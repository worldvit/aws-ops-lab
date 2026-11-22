#!/bin/bash
# scale 모듈 정상 상태 판정 공통 — baseline/verify.sh 와 faults/*/verify.sh 가 source 한다.
#   verify_main "<제목>"  → PASS/FAIL 을 출력하고 종료 코드(0=정상)로 끝낸다
# 지금 돌아가는 상태(노드·앱·사용자 경로·부하)에 더해 "늘고 줄어드는 장치가 제자리에 있는가"(HPA·metrics-server·Karpenter·DB 스냅샷)를 본다.
set -uo pipefail
: "${SID:?SID 환경변수에 학번을 넣으세요. 예) source ~/opslab-env.sh}"
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../common/eks.sh"
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/functions.sh"
PASS=0; FAIL=0
ok() { echo "  [PASS] $*"; PASS=$((PASS+1)); }
ng() { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }
NS=$APP_NS
summary() { echo "== 결과: PASS $PASS / FAIL $FAIL =="; [ "$FAIL" -eq 0 ] && { echo "판정: 정상"; exit 0; } || { echo "판정: 비정상"; exit 1; }; }

verify_main() {
  kube_login || { echo "클러스터 $CLUSTER 에 접속하지 못했습니다(kubeconfig)."; exit 2; }
  echo "== $(TZ=Asia/Seoul date '+%F %T') 정상 상태 판정: $SID / $1 =="

  echo "[1] 노드 (전부 Ready, 점검 중 표시 없음)"
  local nn nr nc
  local ns; ns=$(nodes_settled)   # 막 들어오는 노드(3분 미만)는 빼고 본다
  nn=$(grep -c . <<<"$ns"); nr=$(grep -c ' True ' <<<"$ns"); nc=$(kubectl get nodes --no-headers | grep -c SchedulingDisabled)
  [ "$nn" -ge 2 ] && [ "$nr" -eq "$nn" ] && ok "노드 $nr/$nn Ready" || ng "노드 Ready $nr/$nn (기준: 2대 이상 전부 Ready)"
  [ "$nc" -eq 0 ] && ok "점검 중(cordon) 노드 없음" || ng "점검 중(SchedulingDisabled) 노드 $nc 대 — 점검이 끝났으면 kubectl uncordon"

  echo "[2] 파드 (자리를 못 잡은 Pending 없음, 샘플 앱 Available)"
  local pp av want
  pp=$(pending_pods)
  [ -z "$pp" ] && ok "Pending 파드 없음" || { ng "Pending 파드 $(wc -l <<<"$pp")개: $(head -3 <<<"$pp" | tr '\n' ' ')"; }
  read -r av want <<<"$(kubectl -n "$NS" get deploy opslab-app -o json 2>/dev/null | jq -r '"\(.status.availableReplicas // 0) \(.spec.replicas // 0)"')"
  [ "${av:-0}" -ge 2 ] && [ "$av" -eq "$want" ] && ok "샘플 앱 Available $av/$want" || ng "샘플 앱 Available ${av:-0}/${want:-?}"

  echo "[3] HPA (파드 수 자동 조절 — 지표를 읽고, 대상을 찾고, 늘릴 여지가 있음)"
  local h ms min max tgt req cur
  ms=$(kubectl -n kube-system get deploy metrics-server -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [ "${ms:-0}" -ge 1 ] && ok "metrics-server Ready ${ms}개(지표 공급)" || ng "metrics-server 가 Ready 가 아닙니다(${ms:-0}개) — HPA 가 CPU 를 읽지 못합니다"
  h=$(hpa_json)
  if [ -z "$h" ]; then ng "HPA(opslab-app)가 없습니다(구축 1)"
  else
    read -r min max tgt <<<"$(jq -r '"\(.spec.minReplicas) \(.spec.maxReplicas) \(.spec.scaleTargetRef.kind)/\(.spec.scaleTargetRef.name)"' <<<"$h")"
    [ "$tgt" = Deployment/opslab-app ] && kubectl -n "$NS" get deploy opslab-app >/dev/null 2>&1 && ok "대상 $tgt 있음" || ng "HPA 대상 $tgt 를 찾을 수 없습니다"
    [ "$max" -gt "$min" ] && ok "최소 $min < 최대 $max (늘릴 여지)" || ng "최소 $min · 최대 $max — 파드 수를 바꿀 수 없습니다"
    cur=$(jq -r '.status.currentMetrics[0].resource.current.averageUtilization // empty' <<<"$h")
    [ -n "$cur" ] && ok "현재 CPU 사용률 ${cur}% (목표 $(jq -r '.spec.metrics[0].resource.target.averageUtilization' <<<"$h")%)" || ng "HPA 가 CPU 사용률을 읽지 못합니다(<unknown>) — kubectl -n app describe hpa opslab-app"
  fi
  req=$(kubectl -n "$NS" get deploy opslab-app -o jsonpath='{.spec.template.spec.containers[?(@.name=="app")].resources.requests.cpu}' 2>/dev/null)
  [ -n "$req" ] && ok "앱 컨테이너 CPU 요청(requests) $req" || ng "앱 컨테이너에 CPU 요청(requests)이 없습니다 — HPA 사용률의 분모가 없습니다"

  echo "[4] Karpenter (노드 자동 공급 — 컨트롤러·NodePool·EC2NodeClass)"
  local kr lim
  kr=$(kubectl -n kube-system get deploy karpenter -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [ "${kr:-0}" -ge 1 ] && ok "Karpenter 컨트롤러 Ready" || ng "Karpenter 컨트롤러가 Ready 가 아닙니다"
  [ "$(nc_json | jq -r '[.status.conditions[]?|select(.type=="Ready")][0].status')" = True ] && ok "EC2NodeClass default Ready(서브넷·보안 그룹·AMI 찾음)" \
    || ng "EC2NodeClass default 가 Ready 가 아닙니다: $(nc_json | jq -r '[.status.conditions[]?|select(.status!="True")|"\(.type): \(.message)"]|join("; ")' 2>/dev/null | cut -c1-160)"
  [ "$(np_json | jq -r '[.status.conditions[]?|select(.type=="Ready")][0].status')" = True ] && ok "NodePool default Ready" || ng "NodePool default 가 Ready 가 아닙니다"
  lim=$(np_json | jq -r '.spec.limits.cpu // "없음"')
  [ "$lim" = 16 ] && ok "NodePool 자원 한도 cpu $lim" || ng "NodePool 자원 한도가 기준(16)과 다릅니다: cpu $lim"
  [ "$(np_json | jq -r '[.spec.template.spec.requirements[]|select(.key=="karpenter.k8s.aws/instance-size")|.values]|flatten|sort|join(",")')" = large,xlarge ] \
    && ok "NodePool 인스턴스 크기 조건 large·xlarge" || ng "NodePool 인스턴스 조건이 기준과 다릅니다: $(np_json | jq -c '[.spec.template.spec.requirements[]|{(.key|split("/")|last):.values}]')"

  echo "[5] DB (PostgreSQL·Redis, 디스크·스냅샷·기준 데이터)"
  local pg rd
  pg=$(kubectl -n "$NS" get pod postgres-0 -o jsonpath='{.status.phase}' 2>/dev/null); rd=$(kubectl -n "$NS" get deploy redis -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [ "$pg" = Running ] && ok "PostgreSQL Running" || ng "PostgreSQL ${pg:-없음}"
  [ "${rd:-0}" -ge 1 ] && ok "Redis Ready" || ng "Redis 가 Ready 가 아닙니다"
  [ "$(pg_marker)" = scale-baseline ] && ok "기준 데이터(opslab_marker) 있음" || ng "기준 데이터(opslab_marker)가 없습니다 — 디스크가 바뀌었을 수 있습니다"
  [ "$(snap_ready)" = true ] && ok "스냅샷 pg-baseline 사용 가능" || ng "스냅샷 pg-baseline 이 없거나 준비되지 않았습니다(구축 4)"

  echo "[6] 사용자 경로 (ALB — /health 3회, /api 5회, /db 2회)"
  local host bad c p
  host=$(kubectl -n "$NS" get ingress opslab-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null); bad=""
  if [ -z "$host" ]; then ng "Ingress(ALB) 주소가 없습니다"
  else
    for p in /health /health /health /api /api /api /api /api /db /db; do
      c=$(curl -s -o /dev/null -m 8 -w '%{http_code}' "http://$host$p"); [ "$c" = 200 ] || bad="$bad $p=$c"; done
    [ -z "$bad" ] && ok "모든 경로 200 응답" || ng "200 이 아닌 경로:$bad"
  fi

  echo "[7] 부하 파드 최근 1분 (ALB 로 초당 10건)"
  local lp lines e5 ce rq
  lp=$(kubectl -n "$NS" get pods -l app.kubernetes.io/name=opslab-load --field-selector=status.phase=Running -o name 2>/dev/null | head -1)
  lines=$([ -n "$lp" ] && kubectl -n "$NS" logs "$lp" --since=70s 2>/dev/null | grep 'req=' | tail -6)
  if [ -z "$lines" ]; then ng "요청 수 0건 — 부하 파드가 없습니다: bash ~/opslab/common/load.sh pod alb"
  else
    rq=$(grep -o 'req=[0-9]*' <<<"$lines" | cut -d= -f2 | awk '{s+=$1}END{print s+0}')
    e5=$(grep -o '5xx=[0-9]*' <<<"$lines" | cut -d= -f2 | awk '{s+=$1}END{print s+0}')
    ce=$(grep -o 'conn_err=[0-9]*' <<<"$lines" | cut -d= -f2 | awk '{s+=$1}END{print s+0}')
    [ "$e5" -eq 0 ] && [ "$ce" -eq 0 ] && ok "요청 $rq건 중 5xx 0건·연결 오류 0건" || ng "요청 $rq건 중 5xx $e5건·연결 오류 $ce건 (기준 0건)"
  fi
  summary
}
