#!/bin/bash
# auto patch — rollback. 유지관리 기간을 켜고, 대상 태그를 앱 서버 이름으로 되돌린다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
W=$(aws ssm describe-maintenance-windows --filters Key=Name,Values="$MW" --query 'WindowIdentities[0].WindowId' --output text)
aws ssm update-maintenance-window --window-id "$W" --enabled >/dev/null && echo "  유지관리 기간 켬"
for T in $(aws ssm describe-maintenance-window-targets --window-id "$W" --query 'Targets[].WindowTargetId' --output text); do
  aws ssm update-maintenance-window-target --window-id "$W" --window-target-id "$T" --targets Key=tag:Name,Values="$APP_TAG" >/dev/null && echo "  대상 태그 → $APP_TAG"
done
exit 0
