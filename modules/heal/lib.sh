#!/bin/bash
# heal 모듈 장애 스크립트 공통: 공통 함수 + EKS 함수 + heal 함수(functions.sh) + 내 Fork·오늘 브랜치
D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
source "$D/../../common/lib.sh"
source "$D/../../common/eks.sh"
kube_login || { echo "클러스터 $CLUSTER 에 접속하지 못했습니다."; exit 3; }
source "$D/functions.sh"
R=$(fork_repo); B=$(fork_branch)
[ -n "$R" ] && [ -n "$B" ] || { echo "루트 앱(opslab-root)이 없습니다. 환경 층(start.sh heal)을 먼저 배포하세요."; exit 3; }
ro_json >/dev/null || { echo "Rollout(opslab-app)이 없습니다. 1단계 구축 3을 먼저 끝내세요."; exit 3; }
GH_T=$(gh_token); [ -n "$GH_T" ] || { echo "GitHub 토큰 시크릿(opslab/github-token)이 없습니다."; exit 3; }
export GH_T
# 영향 범위: 내 Fork 오늘 브랜치의 운영 값 파일(커밋 추가 — 원복은 주입 전 커밋으로 되돌림), app 네임스페이스의 PostgreSQL 파드 수(heal-1 ①),
#           노드 cordon·드레인(앱 파드만), 노드 그룹 자동 복구 설정·노드의 kubelet(heal-5), FIS 실험 <학번>-heal-az-fault(heal-3 ③).
#           kube-system·강사/FIS 접근 항목·계정 IAM·원본 저장소는 바꾸지 않는다.
set -e
base_save() { save base "$(gh_head "$R" "$B")"; }
commit() { gh_edit "$R" "$B" "$PV" "$1" "$2"; }               # $1=커밋 메시지 $2=sed 식 — 운영 값 파일을 고친다
kick() { app_refresh $APPS; }
release() {  # $1=버전 [$2=오류율] — 새 버전 릴리스 커밋(APP_VERSION 을 바꾸면 카나리가 시작된다)
  local e='s/^  APP_VERSION: .*/  APP_VERSION: '"$1"'/'
  [ -n "${2:-}" ] && e="$e; s/^  APP_WARMUP_SEC: .*/&\n  APP_ERROR_RATE: \"$2\"   # 결제 화면 개선(새 연동 포함)/"
  commit "${3:-릴리스 $1}" "$e"
}
wait_rev() {  # Rollout 의 원하는 상태(spec)가 조건을 만족할 때까지 — Argo CD 가 커밋을 반영했는지
  local i; for i in $(seq 1 40); do ro_json | jq -e "$1" >/dev/null && return 0; [ $((i % 4)) -eq 0 ] && kick; sleep 5; done; return 1
}
app_nodes() { kubectl -n "$APP_NS" get pods -l app.kubernetes.io/instance=opslab-app -o json | jq -r '.items[] | select((.metadata.ownerReferences[0].kind // "")!="Job") | select(.status.phase=="Running") | .spec.nodeName' | sort -u; }
pg_node() { kubectl -n "$APP_NS" get pod postgres-0 -o jsonpath='{.spec.nodeName}' 2>/dev/null; }
node_zone() { kubectl get node "$1" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}'; }
fis_stop() {
  local e t
  for e in $(aws fis list-experiments --query "experiments[?state.status=='running' && tags.Module=='heal'].id" --output text 2>/dev/null); do aws fis stop-experiment --id "$e" >/dev/null 2>&1 && echo "  FIS 실험 중지: $e"; done
  for t in $(aws fis list-experiment-templates --query "experimentTemplates[?tags.Module=='heal'].id" --output text 2>/dev/null); do aws fis delete-experiment-template --id "$t" >/dev/null 2>&1; done
}
restore() {  # 원복: FIS 중지 → 브랜치를 주입 전 커밋으로 → DB·노드·자동 복구·kubelet 정상화 → 파드 AZ 재분산 → Rollout Healthy 까지
  set +e
  local b n i
  fis_stop
  b=$(load base)
  [ -n "$b" ] && [ "$b" != None ] && [ "$(gh_head "$R" "$B")" != "$b" ] && gh_reset "$R" "$B" "$b" && echo "  브랜치 $B → ${b:0:7} (주입 전 커밋)"
  [ "$(kubectl -n "$APP_NS" get sts postgres -o jsonpath='{.spec.replicas}' 2>/dev/null)" = 0 ] && kubectl -n "$APP_NS" scale sts postgres --replicas=1 >/dev/null && echo "  PostgreSQL 다시 1개"
  for n in $(kubectl get nodes --no-headers | awk '$2 ~ /SchedulingDisabled/ {print $1}'); do kubectl uncordon "$n" >/dev/null && echo "  uncordon $n"; done
  for n in $(kubectl get nodes --no-headers | awk '$2 !~ /^Ready/ {print $1}'); do on_node "$n" "systemctl start kubelet" >/dev/null 2>&1 && echo "  kubelet 다시 시작: $n"; done
  repair_on && echo "  노드 자동 복구 설정 → 기준(켜짐·절반 넘으면 멈춤·한 번에 1대)"
  for i in $(seq 1 40); do [ "$(nodes_ready)" -ge 3 ] && break; sleep 15; done
  for a in $APPS; do app_terminate "$a"; done
  kick; sleep 10; app_sync opslab-root; sleep 20; app_terminate opslab-prod; app_sync opslab-prod
  # 되돌리는 대상은 이미 검증된 이전 버전이다 — 결함 stable 이 섞인 채로 분석을 다시 타면 되돌리기마저 중단되므로 단계·분석을 건너뛴다(긴급 롤백)
  if ! ro_wait 120; then
    [ "$(ro_json | jq -r '.status.abort // false')" = true ] && kubectl argo rollouts retry rollout opslab-app -n "$APP_NS" >/dev/null 2>&1 && sleep 5
    kubectl argo rollouts promote opslab-app -n "$APP_NS" --full >/dev/null 2>&1 && echo "  긴급 롤백: kubectl argo rollouts promote --full (단계·분석 건너뜀)"
    ro_wait 600
  fi
  if [ "$(zones_of_app | wc -l)" -lt 2 ]; then   # 파드가 한 노드·AZ 에 몰려 있으면 다시 나눈다(차례로 다시 시작)
    kubectl -n "$APP_NS" patch rollout opslab-app --type merge -p "{\"spec\":{\"restartAt\":\"$(date -u +%FT%TZ)\"}}" >/dev/null && echo "  파드 다시 시작(AZ 재분산)"
    sleep 30; ro_wait 600
  fi
  ro_wait 120 && echo "  Rollout $(ro_line | cut -d' ' -f1), 파드 AZ: $(zones_of_app | tr '\n' ' ')" || echo "  ⚠️ Rollout 이 아직 Healthy 가 아닙니다: $(ro_line) — 1~2분 뒤 verify.sh"
}
