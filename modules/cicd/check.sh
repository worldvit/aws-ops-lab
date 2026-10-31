#!/bin/bash
# cicd 모듈 verify 공통. verify.sh 들이 source 한다.
CICD_NO_LAB=1 source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"
PASS=0; FAIL=0
ok() { echo "  [PASS] $*"; PASS=$((PASS+1)); }
ng() { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }
start() { echo "== $(date '+%F %T') 정상 상태 판정: $SID / cicd $1 =="; }
chk_last() {  # 마지막 파이프라인 실행이 성공
  local id s; read -r id s <<<"$(last_exec)"
  [ "$s" = Succeeded ] && ok "마지막 파이프라인 실행 Succeeded (${id:0:8})" || ng "마지막 파이프라인 실행 ${s:-없음} (${id:0:8}) — $(failed_actions "$id" | head -1 | cut -c1-120)"
}
chk_version() {  # EC2(80)·ECS(8000) 모두 기록된 릴리스 번호로 5/5 성공
  local want v n; want=$(release)
  read -r v n <<<"$(ver 80)";   [ "$v" = "$want" ] && [ "$n" = 5/5 ] && ok "EC2(:80) /api 버전 $v $n" || ng "EC2(:80) /api 기대 $want — 실제 $v, 성공 $n"
  read -r v n <<<"$(ver 8000)"; [ "$v" = "$want" ] && [ "$n" = 5/5 ] && ok "ECS(:8000) /api 버전 $v $n" || ng "ECS(:8000) /api 기대 $want — 실제 $v, 성공 $n"
}
chk_guard() {  # 두 배포 그룹 모두 실패·알람 시 자동 롤백 + 알람 연결
  local a dg; for a in "$EC2APP:$EC2DG" "$ECSAPP:$ECSDG"; do
    dg=$(aws deploy get-deployment-group --application-name "${a%%:*}" --deployment-group-name "${a##*:}" \
      --query 'deploymentGroupInfo.[autoRollbackConfiguration.enabled,alarmConfiguration.enabled,length(alarmConfiguration.alarms)]' --output text 2>/dev/null)
    [ "$dg" = "True	True	1" ] && ok "배포 그룹 ${a##*:}: 자동 롤백·알람 중단 켜짐" || ng "배포 그룹 ${a##*:}: 자동 롤백·알람 설정 [$dg] (기대 True True 1)"
  done
}
finish() {
  echo "== 결과: PASS $PASS / FAIL $FAIL =="
  if [ "$FAIL" -eq 0 ]; then echo "판정: 정상 (verify 통과) — 기록표에 '복구 완료 시각'과 '통과'를 적으세요"; exit 0
  else echo "판정: 비정상"; exit 1; fi
}
