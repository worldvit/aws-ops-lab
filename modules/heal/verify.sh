#!/bin/bash
# heal 모듈 정상 상태 판정 공통 — baseline/verify.sh 와 faults/*/verify.sh 가 source 한다.
#   verify_main "<제목>"  → PASS/FAIL 을 출력하고 종료 코드(0=정상)로 끝낸다
# 지금 돌아가는 상태(노드·Rollout·파드·사용자 경로·부하)에 더해 "무중단 장치가 제자리에 있는가"(probe 역할·PDB·AZ 분산·카나리 판정·노드 자동 복구)를 본다.
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

  echo "[1] 노드 (3대 모두 Ready, 점검 중 표시 없음)"
  local nn nr nc
  nn=$(kubectl get nodes --no-headers | wc -l); nr=$(nodes_ready); nc=$(kubectl get nodes --no-headers | grep -c SchedulingDisabled)
  [ "$nn" -ge 3 ] && [ "$nr" -eq "$nn" ] && ok "노드 $nr/$nn Ready" || ng "노드 Ready $nr/$nn (기준: 3대 이상 전부 Ready)"
  [ "$nc" -eq 0 ] && ok "점검 중(cordon) 노드 없음" || ng "점검 중(SchedulingDisabled) 노드 $nc 대 — 점검이 끝났으면 kubectl uncordon"

  echo "[2] 운영 앱 Rollout (app/opslab-app)"
  local j ph want rdy bad
  j=$(ro_json)
  if [ -z "$j" ]; then ng "Rollout 이 없습니다(구축 3)"
  else
    read -r ph want rdy <<<"$(jq -r '[.status.phase // "-", .spec.replicas // 0, .status.readyReplicas // 0] | @tsv' <<<"$j")"
    [ "$ph" = Healthy ] && [ "$(jq -r '.status.stableRS == .status.currentPodHash' <<<"$j")" = true ] \
      && ok "Rollout Healthy — 새 버전이 stable (Ready $rdy/$want)" || ng "Rollout $ph: $(ro_line | cut -d' ' -f2-) — kubectl argo rollouts get rollout opslab-app -n app"
  fi
  bad=$(kubectl -n "$NS" get pods -l app.kubernetes.io/name=opslab-app,app.kubernetes.io/instance=opslab-app -o json 2>/dev/null | jq -r '.items[]
        | select(.metadata.deletionTimestamp==null) | select((.metadata.ownerReferences[0].kind // "")!="Job")
        | select(.status.phase!="Running" or ([.status.containerStatuses[]?|.ready]|all|not) or ([.status.containerStatuses[]?|select(.name=="app")|.restartCount]|add // 0) > 1)
        | "\(.metadata.name) 재시작 \([.status.containerStatuses[]?|select(.name=="app")|.restartCount]|add // 0)회 \([.status.containerStatuses[]? | .state.waiting.reason // empty] | join(","))"')
  [ -z "$bad" ] && ok "앱 파드 모두 Running·Ready, 재시작 1회 이하" || { ng "Ready 가 아니거나 재시작을 되풀이하는 앱 파드:"; sed 's/^/         /' <<<"$bad"; }

  echo "[3] Argo CD 앱"
  local a l
  for a in $APPS; do l=$(app_line "$a"); [[ "$l" == "Synced Healthy "* ]] && ok "$a Synced·Healthy" || ng "$a: $l"; done
  [ "$(app_json opslab-prod | jq -r '.spec.syncPolicy.automated.selfHeal // false')" = true ] && ok "운영 앱 자동 치유(selfHeal) 켜짐" || ng "운영 앱 자동 치유가 꺼져 있습니다"

  echo "[4] 건강검진(probe) 역할 — startup 있음, liveness 는 얕게(/health), readiness 는 준비 상태(/ready)"
  local sp lp rp
  sp=$(probe_path startupProbe); lp=$(probe_path livenessProbe); rp=$(probe_path readinessProbe)
  [ -n "$sp" ] && ok "startup probe $sp (느린 시작을 기다려 줌)" || ng "startup probe 가 없습니다 — 35초 걸려 뜨는 앱을 liveness 가 죽입니다"
  [ "$lp" = /health ] && ok "liveness $lp (프로세스만 확인)" || ng "liveness 경로 '$lp' — DB 같은 바깥 의존성을 보면 의존성 장애 때 전부 재시작합니다(기준 /health)"
  [ "$rp" = /ready ] && ok "readiness $rp (데우기 끝나야 손님 받음)" || ng "readiness 경로 '${rp:-없음}' — 준비 중인 파드가 손님을 받습니다(기준 /ready)"

  echo "[5] 무중단 장치 — PDB·AZ 분산"
  local pj al
  pj=$(pdb_json)
  if [ -n "$pj" ]; then al=$(jq -r '.status.disruptionsAllowed // 0' <<<"$pj")
    [ "$al" -ge 1 ] && ok "PDB 있음 — 지금 1개 이상 내려가도 됨(disruptionsAllowed=$al)" || ng "PDB 가 드레인을 막습니다(disruptionsAllowed=$al, $(jq -c '.spec | del(.selector)' <<<"$pj"))"
  else ng "PDB 가 없습니다 — 점검 때 파드가 한꺼번에 내려갈 수 있습니다"; fi
  [ "$(ro_json | jq -r '[.spec.template.spec.topologySpreadConstraints[]? | select(.topologyKey=="topology.kubernetes.io/zone")] | length')" -ge 1 ] \
    && ok "AZ 분산 규칙(topology spread) 있음" || ng "AZ 분산 규칙이 없습니다"
  local zs; zs=$(zones_of_app | wc -l)
  [ "$zs" -ge 2 ] && ok "앱 파드가 AZ $zs 곳에 나뉘어 있음 ($(zones_of_app | tr '\n' ' '))" || ng "앱 파드가 한 AZ 에 몰려 있습니다 ($(zones_of_app | tr '\n' ' '))"
  [ -z "$(ro_json | jq -r '.spec.template.spec.nodeSelector // {} | keys[]?')" ] && ok "노드 고정(nodeSelector) 없음" || ng "파드가 특정 노드·AZ 에 고정돼 있습니다: $(ro_json | jq -c '.spec.template.spec.nodeSelector')"

  echo "[6] 카나리 판정(AnalysisTemplate opslab-app-canary)"
  local at q er lt
  at=$(kubectl -n "$NS" get analysistemplate opslab-app-canary -o json 2>/dev/null)
  if [ -n "$at" ]; then
    q=$(jq -r '.spec.metrics[] | select(.name=="error-rate") | .provider.cloudWatch.metricDataQueries[] | select(.id=="ok") | .expression' <<<"$at")
    er=$(jq -r '.spec.metrics[] | select(.name=="error-rate") | .successCondition' <<<"$at" | grep -o '<= *[0-9.]*' | tr -dc '0-9.')
    lt=$(jq -r '.spec.metrics[] | select(.name=="latency") | .successCondition' <<<"$at" | grep -o '<= *[0-9.]*' | tr -dc '0-9.')
    grep -q 'MetricName="HTTPCode_Target_2XX_Count"' <<<"$q" && ok "정상 응답 지표 이름 맞음(HTTPCode_Target_2XX_Count)" || ng "정상 응답 지표가 이상합니다: $q — 데이터가 없으면 판정이 늘 통과합니다"
    awk -v e="${er:-9}" -v l="${lt:-0}" 'BEGIN{exit !(e<=0.1 && e>0 && l>=0.1)}' && ok "판정 기준: 오류율 ≤ $er, 응답시간 ≤ ${lt}s" || ng "판정 기준이 이상합니다: 오류율 ≤ ${er:-?}, 응답시간 ≤ ${lt:-?}s (기준 0.05·0.5)"
  else ng "분석 템플릿이 없습니다"; fi

  echo "[7] 노드 자동 복구"
  local rc; rc=$(ng_json | jq -c '.nodeRepairConfig // {}')
  [ "$(jq -r '.enabled // false' <<<"$rc")" = true ] && ok "자동 복구 켜짐" || ng "자동 복구가 꺼져 있습니다 — 고장 난 노드가 그대로 남습니다"
  [ "$(jq -r '(.maxUnhealthyNodeThresholdPercentage // .maxUnhealthyNodeThresholdCount // 0) > 0 and (.maxParallelNodesRepairedCount // .maxParallelNodesRepairedPercentage // 0) > 0' <<<"$rc")" = true ] \
    && ok "교체 범위 제한 있음(절반 넘게 아프면 멈춤·한 번에 $(jq -r '.maxParallelNodesRepairedCount // .maxParallelNodesRepairedPercentage' <<<"$rc"))" || ng "교체 범위 제한이 없습니다 — 공통 원인일 때 노드를 한꺼번에 교체합니다: $rc"
  local fx; fx=$(aws fis list-experiments --query "experiments[?state.status=='running' && tags.Module=='heal'].id" --output text 2>/dev/null)
  [ -z "$fx" ] && ok "진행 중인 장애 실험(FIS) 없음" || ng "진행 중인 FIS 실험: $fx"

  echo "[8] 사용자 경로 (ALB — /health 3회, /api 10회)"
  local alb c bad2=""
  alb=$(kubectl -n "$NS" get ingress opslab-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  if [ -n "$alb" ]; then
    for i in 1 2 3; do c=$(curl -s -o /dev/null -m 8 -w '%{http_code}' "http://$alb/health"); [ "$c" = 200 ] || { bad2="$bad2 /health=$c"; break; }; done
    for i in $(seq 1 10); do c=$(curl -s -o /dev/null -m 8 -w '%{http_code}' "http://$alb/api"); [ "$c" = 200 ] || { bad2="$bad2 /api=$c"; break; }; done
    [ -z "$bad2" ] && ok "모든 경로 200 응답" || ng "200 이 아닌 경로:$bad2"
  else ng "Ingress 에 ALB 주소가 없습니다"; fi

  echo "[9] 부하 파드 최근 1분 (ALB 로 초당 10건)"
  local lp lines e5 ce req
  lp=$(kubectl -n "$NS" get pods -l app.kubernetes.io/name=opslab-load --field-selector=status.phase=Running -o name 2>/dev/null | head -1)
  lines=$([ -n "$lp" ] && kubectl -n "$NS" logs "$lp" --since=70s 2>/dev/null | grep 'req=' | tail -6)
  if [ -z "$lines" ]; then ng "요청 수 0건 — 부하 파드가 없습니다: bash ~/opslab/common/load.sh pod alb"
  else
    req=$(grep -o 'req=[0-9]*' <<<"$lines" | cut -d= -f2 | awk '{s+=$1}END{print s+0}')
    e5=$(grep -o '5xx=[0-9]*' <<<"$lines" | cut -d= -f2 | awk '{s+=$1}END{print s+0}')
    ce=$(grep -o 'conn_err=[0-9]*' <<<"$lines" | cut -d= -f2 | awk '{s+=$1}END{print s+0}')
    [ "$e5" -eq 0 ] && [ "$ce" -eq 0 ] && ok "요청 $req건 중 5xx 0건·연결 오류 0건" || ng "요청 $req건 중 5xx $e5건·연결 오류 $ce건 (기준 0건)"
  fi
  summary
}
