#!/bin/bash
# heal-4 selfheal — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: 운영 값 파일 커밋(rollout.analysis·APP_ERROR_RATE), Rollout 의 환경변수(당직자 긴급 조치 흉내 — 자동 치유가 되돌린다)
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 1); base_save
# "급한 릴리스라 분석을 잠시 끔" + 새 연동이 든 v3(오류 30%) → 카나리 판정 없이 끝까지 나감
commit "급한 릴리스: 카나리 분석 잠시 끔" '/^  analysis:/,/^    maxLatency:/ s/^    enabled: true/    enabled: false/'
sleep 5; release v3 0.3 "제휴사 연동 릴리스 v3"
wait_rev '[.spec.template.spec.containers[]|select(.name=="app")|.env[]?|select(.name=="APP_ERROR_RATE")|.value]|.[0]=="0.3"'
ro_wait 600 || true
# 당직자 긴급 조치: 클러스터에서 바로 오류율을 0 으로 — 자동 치유(selfHeal)가 Git 값으로 되돌린다
I=$(ro_json | jq '[.spec.template.spec.containers[0].env[].name] | index("APP_ERROR_RATE")')
kubectl -n "$APP_NS" patch rollout opslab-app --type json -p "[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/env/$I/value\",\"value\":\"0\"}]" >/dev/null || true
record $V
