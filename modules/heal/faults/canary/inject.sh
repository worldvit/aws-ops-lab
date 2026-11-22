#!/bin/bash
# heal-2 canary — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: 운영 값 파일 커밋(rollout.analysis·APP_VERSION·APP_ERROR_RATE)
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 2); base_save
case $V in
  1) # 오류율 기준을 "완화"했다(60% — 오류가 절반이어도 통과) + 결함 있는 새 버전(오류 50%)
     commit "오류율 기준 완화: 일시적 오류로 배포가 멈추지 않게" 's#^    maxErrorRate: .*#    maxErrorRate: "0.6"#'
     sleep 5; release v3 0.5 "결제 화면 개선 릴리스 v3" ;;
  2) # 응답시간 기준을 "강화"했다(0.1ms — 어떤 버전도 못 넘음) + 정상인 새 버전
     commit "응답시간 기준 강화" 's#^    maxLatency: .*#    maxLatency: "0.0001"#'
     sleep 5; release v3 "" "검색 화면 개선 릴리스 v3" ;;
esac
wait_rev '[.spec.template.spec.containers[]|select(.name=="app")|.env[]?|select(.name=="APP_VERSION")|.value]|.[0]=="v3"'
record $V
