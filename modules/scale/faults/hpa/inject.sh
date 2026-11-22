#!/bin/bash
# scale-1 hpa — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: kube-system metrics-server 파드 수(①), 샘플 앱 Deployment 의 CPU 요청(②), HPA 대상 이름(③), 트래픽 급증 파드(opslab-spike)
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 3)
case $V in
  1) # 지표 공급(metrics-server)이 멈췄다 — "쓰지 않는 애드온 정리" 중 파드 수를 0 으로
     kubectl -n kube-system scale deploy metrics-server --replicas=0 >/dev/null ;;
  2) # 앱 매니페스트 "정리"로 CPU 요청(requests)이 빠졌다 — HPA 사용률의 분모가 없다
     I=$(kubectl -n "$APP_NS" get deploy opslab-app -o json | jq '[.spec.template.spec.containers[].name] | index("app")')
     kubectl -n "$APP_NS" patch deploy opslab-app --type json -p "[{\"op\":\"remove\",\"path\":\"/spec/template/spec/containers/$I/resources/requests\"}]" >/dev/null
     kubectl -n "$APP_NS" rollout status deploy opslab-app --timeout=300s >/dev/null ;;
  3) # HPA 를 다시 만들며 대상 이름을 잘못 적었다
     kubectl -n "$APP_NS" patch hpa opslab-app --type merge -p '{"spec":{"scaleTargetRef":{"name":"opslab-ap"}}}' >/dev/null ;;
esac
spike start 3        # 이벤트 시작 — 트래픽 급증
record $V
