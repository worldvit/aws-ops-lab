#!/bin/bash
# cicd bad-release — rollback. 이전 정상 릴리스(오류율 0)를 다시 배포하고, 두 배포 그룹의 알람 중단·자동 롤백을 켠다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
need_pipe
# 오류가 남아 있으면 알람이 ALARM 이라 복귀 배포마저 중단된다 → 복귀하는 동안만 알람 중단을 끄고, 끝나면 켠다
# 주의: 끌 때도 알람 이름을 함께 줘야 한다(enabled=false 만 주면 InvalidAlarmConfigException)
for a in "$EC2APP:$EC2DG:$SID-cmp-target-5xx" "$ECSAPP:$ECSDG:$SID-cicd-ecs-5xx"; do
  IFS=: read -r app dg al <<<"$a"
  aws deploy update-deployment-group --application-name "$app" --current-deployment-group-name "$dg" --alarm-configuration "enabled=false,alarms=[{name=$al}]" >/dev/null \
    && echo "  $dg 알람 중단 잠시 끔" || echo "  $dg 알람 중단 끄기 실패"
done
P=$(load prev_release); [ -n "$P" ] && [ "$P" != None ] || P=v1
r=$(redeploy_good "$P"); echo "  이전 릴리스 $P 재배포(알람 중단 잠시 끔): $r"
for a in "$EC2APP:$EC2DG:$SID-cmp-target-5xx" "$ECSAPP:$ECSDG:$SID-cicd-ecs-5xx"; do
  IFS=: read -r app dg al <<<"$a"
  aws deploy update-deployment-group --application-name "$app" --current-deployment-group-name "$dg" \
    --alarm-configuration "enabled=true,alarms=[{name=$al}]" \
    --auto-rollback-configuration enabled=true,events=DEPLOYMENT_FAILURE,DEPLOYMENT_STOP_ON_ALARM >/dev/null && echo "  $dg 알람 중단·자동 롤백 다시 켬"
done
