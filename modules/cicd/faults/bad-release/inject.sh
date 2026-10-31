#!/bin/bash
# cicd bad-release — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: 오류를 내는 설정(ErrorRate)이 담긴 새 릴리스 1회(변형 2는 두 배포 그룹의 알람 중단 기능도 끔). 15분간 :80·:8000 으로 시험 트래픽.
need_pipe
V_=$(pick_variant 2)
save prev_release "$(good_release)"
if [ "$V_" = 2 ]; then
  aws deploy update-deployment-group --application-name "$EC2APP" --current-deployment-group-name "$EC2DG" --alarm-configuration enabled=false >/dev/null &&
  aws deploy update-deployment-group --application-name "$ECSAPP" --current-deployment-group-name "$ECSDG" --alarm-configuration enabled=false >/dev/null || exit 1
fi
traffic 1500
E=$(start_release "$(new_ver)" 0.3) || exit 1; save exec "$E"
r=$(AUTO_APPROVE=1 wait_exec "$E" 1800)
case $V_ in 1) [ "$r" = Failed ] || exit 1 ;; 2) [ "$r" = Succeeded ] || exit 1 ;; esac
record $V_
