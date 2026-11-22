#!/bin/bash
# heal 따라잡기(start.sh heal full)와 시험(tools/test-module.sh heal)이 쓰는 1단계 구축 명령 모음 — 따라하기 페이지의 순서와 같다.
#   구축 1 노드 3대·자동 복구 → 구축 2 Argo Rollouts → 구축 3 운영 값 커밋(probe·PDB·AZ 분산·카나리) → 구축 4 카나리 연습(v2)
set -uo pipefail
source "$(dirname "$(readlink -f "$0")")/../../common/eks.sh"
source ~/opslab-env.sh
source "$EKS_ROOT/modules/heal/functions.sh"
kube_login
export GH_T=$(gh_token)
R=$(fork_repo); B=$(fork_branch); [ -n "$R" ] && [ -n "$B" ] || { echo "❌ 루트 앱이 없습니다 — bash ~/opslab/common/start.sh heal"; exit 1; }

echo "== 구축 1: 노드 3대(AZ 마다 하나)와 노드 자동 복구"
ng_scale3 || { echo "❌ 노드 그룹 크기 변경 실패"; exit 1; }
repair_on || { echo "❌ 노드 자동 복구 설정 실패"; exit 1; }
for i in $(seq 1 30); do [ "$(nodes_ready)" -ge 3 ] && break; sleep 10; done
echo "   노드 Ready $(nodes_ready)대, 자동 복구 $(ng_json | jq -c '.nodeRepairConfig')"

echo "== 구축 2: Argo Rollouts(카나리 배포 컨트롤러) — IRSA 로 CloudWatch 읽기"
rollouts_role || { echo "❌ IRSA 역할 실패"; exit 1; }
rollouts_install || { echo "❌ Argo Rollouts 설치 실패"; exit 1; }
kubectl -n argo-rollouts rollout status deploy argo-rollouts --timeout=180s >/dev/null && echo "   argo-rollouts 컨트롤러 Running"

echo "== 구축 3: 운영 값 커밋 — probe 재설계·PDB·AZ 분산·카나리 배포 (Deployment → Rollout)"
values_commit || { echo "❌ 운영 값 커밋 실패"; exit 1; }
app_refresh $APPS
for i in $(seq 1 60); do ro_json >/dev/null && break; sleep 10; [ $((i % 3)) -eq 0 ] && app_refresh $APPS; done
ro_wait 900 || { echo "❌ Rollout 이 Healthy 가 되지 않았습니다: $(ro_line)"; exit 1; }
echo "   Rollout $(ro_line), 파드 AZ: $(zones_of_app | tr '\n' ' ')"

echo "== 구축 4: 카나리 연습 — 부하를 켜고 v2 를 커밋해 카나리·분석이 끝까지 가는지 본다"
LT=""; kubectl -n "$APP_NS" get ingress opslab-app >/dev/null 2>&1 && LT=alb
bash "$EKS_ROOT/common/load.sh" pod $LT >/dev/null 2>&1; sleep 90
gh_get "$R" "$B" "$PV" | grep -q 'APP_VERSION: v2' || gh_edit "$R" "$B" "$PV" "v2 릴리스(카나리 연습)" 's/^  APP_VERSION: v1/  APP_VERSION: v2/' || exit 1
app_refresh $APPS
for i in $(seq 1 30); do [ "$(pod_env APP_VERSION)" = v2 ] && break; sleep 10; [ $((i % 3)) -eq 0 ] && app_refresh $APPS; done
ro_wait 900 || { echo "❌ 카나리가 끝나지 않았습니다: $(ro_line)"; kubectl -n "$APP_NS" get analysisrun --sort-by=.metadata.creationTimestamp | tail -3; exit 1; }
echo "   카나리 완료: $(ro_line)"
echo "   분석: $(kubectl -n "$APP_NS" get analysisrun --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].status.phase}')"
echo "✅ heal 구축 완료"
