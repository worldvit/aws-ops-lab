#!/bin/bash
# auto patch — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: 유지관리 기간 $MW 의 사용 여부(v1) 또는 대상 태그(v2). 서버는 건드리지 않는다.
W=$(aws ssm describe-maintenance-windows --filters Key=Name,Values="$MW" --query 'WindowIdentities[0].WindowId' --output text)
[ -n "$W" ] && [ "$W" != None ] || exit 3
save window "$W"
V_=$(pick_variant 2)
case $V_ in
  1) # 장애 대응 중 패치를 멈추려고 기간을 꺼 두고 다시 켜지 않음
     aws ssm update-maintenance-window --window-id "$W" --no-enabled >/dev/null || exit 1 ;;
  2) # 서버 이름 규칙이 바뀔 거라며 대상 태그를 미리 새 이름(…-cmp-app-v2)으로 바꿈
     T=$(aws ssm describe-maintenance-window-targets --window-id "$W" --query 'Targets[0].WindowTargetId' --output text)
     aws ssm update-maintenance-window-target --window-id "$W" --window-target-id "$T" --targets Key=tag:Name,Values="$APP_TAG-v2" >/dev/null || exit 1 ;;
esac
record $V_
