#!/bin/bash
# heal 상태 조회 도우미 — review.yaml·check.sh 가 부른다.  bash ~/opslab/modules/heal/state.sh <질문>
#   probes  : startup 있음 + liveness=/health + readiness=/ready 이면 0
#   pdb     : PDB 가 있고 지금 1개 이상 내려갈 수 있으면 0
#   spread  : AZ 분산 규칙이 있고, 노드 고정이 없고, 앱 파드가 AZ 2곳 이상에 있으면 0
#   analysis: 분석 템플릿이 있고 지표 이름·기준이 정상(오류율 ≤0.1, 응답시간 ≥0.1s)이면 0
#   rollout : Rollout Healthy(새 버전이 stable)면 0
#   repair  : 노드 자동 복구 켜짐 + 절반 넘으면 멈춤(≤50%) + 한 번에 1대(또는 ≤50%)면 0
#   nodes   : 노드 3대 이상 모두 Ready, cordon 없음이면 0
set -uo pipefail
: "${SID:?}"; source "$(dirname "$(readlink -f "$0")")/../../common/eks.sh"; kube_login
source "$EKS_ROOT/modules/heal/functions.sh"
case "${1:-}" in
  probes) [ -n "$(probe_path startupProbe)" ] && [ "$(probe_path livenessProbe)" = /health ] && [ "$(probe_path readinessProbe)" = /ready ] \
            || { echo "startup='$(probe_path startupProbe)' liveness='$(probe_path livenessProbe)' readiness='$(probe_path readinessProbe)'"; exit 1; } ;;
  pdb)    [ "$(pdb_json | jq -r '.status.disruptionsAllowed // 0')" -ge 1 ] || { echo "PDB: $(pdb_json | jq -c '{spec: (.spec|del(.selector)), allowed: .status.disruptionsAllowed}' 2>/dev/null || echo 없음)"; exit 1; } ;;
  spread) [ "$(ro_json | jq '[.spec.template.spec.topologySpreadConstraints[]?|select(.topologyKey=="topology.kubernetes.io/zone")]|length')" -ge 1 ] \
            && [ "$(ro_json | jq '.spec.template.spec.nodeSelector // {} | length')" = 0 ] && [ "$(zones_of_app | wc -l)" -ge 2 ] \
            || { echo "분산 규칙 $(ro_json | jq -c '.spec.template.spec.topologySpreadConstraints // []') 노드 고정 $(ro_json | jq -c '.spec.template.spec.nodeSelector // {}') AZ $(zones_of_app | tr '\n' ' ')"; exit 1; } ;;
  analysis) at=$(kubectl -n "$APP_NS" get analysistemplate opslab-app-canary -o json 2>/dev/null) || { echo "분석 템플릿 없음"; exit 1; }
            jq -e '[.spec.metrics[].provider.cloudWatch.metricDataQueries[]|select(.id=="ok")|.expression][0]|test("MetricName=\"HTTPCode_Target_2XX_Count\"")' <<<"$at" >/dev/null || { echo "지표 이름 이상"; exit 1; }
            er=$(jq -r '.spec.metrics[]|select(.name=="error-rate")|.successCondition' <<<"$at" | grep -o '<= *[0-9.]*' | tr -dc '0-9.')
            lt=$(jq -r '.spec.metrics[]|select(.name=="latency")|.successCondition' <<<"$at" | grep -o '<= *[0-9.]*' | tr -dc '0-9.')
            awk -v e="${er:-9}" -v l="${lt:-0}" 'BEGIN{exit !(e<=0.1 && e>0 && l>=0.1)}' || { echo "기준 오류율 ≤ $er 응답시간 ≤ $lt"; exit 1; } ;;
  rollout) [ "$(ro_json | jq -r '.status.phase')" = Healthy ] && [ "$(ro_json | jq -r '.status.stableRS == .status.currentPodHash')" = true ] || { echo "$(ro_line)"; exit 1; } ;;
  repair) rc=$(ng_json | jq -c '.nodeRepairConfig // {}')
          jq -e '(.enabled // false) and ((.maxUnhealthyNodeThresholdPercentage // 101) <= 50 or (.maxUnhealthyNodeThresholdCount // 99) <= 1)
                 and ((.maxParallelNodesRepairedCount // 99) <= 1 or (.maxParallelNodesRepairedPercentage // 101) <= 50)' <<<"$rc" >/dev/null || { echo "자동 복구 설정 $rc"; exit 1; } ;;
  nodes)  [ "$(nodes_ready)" -ge 3 ] && ! kubectl get nodes --no-headers | grep -q SchedulingDisabled || { kubectl get nodes --no-headers | awk '{print $1, $2}'; exit 1; } ;;
  *) sed -n '2,10p' "$0"; exit 2 ;;
esac
