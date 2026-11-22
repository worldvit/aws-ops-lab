#!/bin/bash
# heal-1 probe — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: 운영 값 파일 커밋(probes), PostgreSQL 파드 수(①, 3분 뒤 스스로 1로 돌아옴)
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 3); base_save
case $V in
  1) # "건강검진 강화" — liveness 가 DB 까지 확인하게 바뀐 뒤(카나리를 무사히 통과), DB 가 3분 동안 멈춘다
     commit "건강검진 강화: liveness 에서 DB 까지 확인" 's#^  liveness:  \{ path: /health,#  liveness:  { path: /health/deep,#'
     wait_rev '[.spec.template.spec.containers[]|select(.name=="app")|.livenessProbe.httpGet.path]|.[0]=="/health/deep"'
     ro_wait 900
     kubectl -n "$APP_NS" scale sts postgres --replicas=0 >/dev/null
     setsid nohup bash -c "sleep 180; kubectl -n $APP_NS scale sts postgres --replicas=1" >/dev/null 2>&1 < /dev/null &
     save dbdown "$(date -u +%FT%TZ)" ;;
  2) # "필요 없는 probe 정리" — startup probe 를 지웠다(35초 걸려 뜨는 앱인데)
     commit "필요 없는 probe 정리(startup 삭제)" 's#^  startup:   \{ path: /health,#  startup:   { path: "",#'
     wait_rev '[.spec.template.spec.containers[]|select(.name=="app")|.startupProbe]|.[0]==null' ;;
  3) # "readiness 단순화" — readiness 를 /health 로(데우기 중에도 200) + 새 버전 릴리스
     commit "readiness 단순화: /health 로 통일" 's#^  readiness: \{ path: /ready, #  readiness: { path: /health,#'
     wait_rev '[.spec.template.spec.containers[]|select(.name=="app")|.readinessProbe.httpGet.path]|.[0]=="/health"' ;;
esac
record $V
