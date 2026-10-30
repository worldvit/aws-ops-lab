#!/bin/bash
# Day 1 replace-loop — rollback. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../common/lib.sh"
aws autoscaling cancel-instance-refresh --auto-scaling-group-name "$ASG" >/dev/null 2>&1 && echo "  인스턴스 새로 고침 취소"
PREV=$(load prev-lt); GRACE=$(load prev-grace)
aws autoscaling update-auto-scaling-group --auto-scaling-group-name "$ASG" \
  --launch-template "LaunchTemplateId=$LT_ID,Version=${PREV:-1}" --health-check-grace-period "${GRACE:-180}" --health-check-type ELB \
  && echo "  LT 버전 ${PREV:-1}, 유예 ${GRACE:-180}초로 원복"
aws autoscaling resume-processes --auto-scaling-group-name "$ASG" && echo "  ASG 프로세스 재개"
echo "  잘못된 버전으로 뜬 인스턴스는 헬스체크 실패로 자동 교체된다(약 5분)"
