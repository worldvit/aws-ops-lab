#!/bin/bash
# iac 모듈 verify 공통. verify.sh 들이 source 한다.
IAC_NO_LAB=1 source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"
PASS=0; FAIL=0
ok() { echo "  [PASS] $*"; PASS=$((PASS+1)); }
ng() { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }
start() { echo "== $(date '+%F %T') 정상 상태 판정: $SID / iac $1 =="; }
chk_stack() {  # 스택이 안정 상태. $1=strict 이면 롤백 완료(이전 버전 복귀)도 실패로 본다(배포 완료가 목표인 Lab)
  local s; s=$(stack_status)
  case "$s" in CREATE_COMPLETE|UPDATE_COMPLETE) ok "스택 $STACK $s";;
    UPDATE_ROLLBACK_COMPLETE) if [ "${1:-}" = strict ]; then ng "스택 $STACK $s — 마지막 업데이트가 실패해 이전 버전으로 돌아가 있음"
      else ok "스택 $STACK $s (이전 버전으로 안정 — 다음 배포 가능)"; fi;;
    *) ng "스택 $STACK $s";; esac
}
chk_promo() {  # /promo 가 스택 매개변수 PromoText 와 같은 문구를 5번 모두 돌려줌
  local want ok=0 i b; want="promo $(sparam PromoText)"
  for i in 1 2 3 4 5; do b=$(curl -s -m 5 "http://$(alb_dns)/promo"); [ "$b" = "$want" ] && ok=$((ok+1)); done
  [ "$ok" = 5 ] && ok "/promo = \"$want\" 5/5" || ng "/promo 기대 \"$want\" — $ok/5, 실제 \"${b:0:60}\""
}
chk_drift() {  # 드리프트 탐지 실행 → IN_SYNC
  local id s; id=$(aws cloudformation detect-stack-drift --stack-name "$STACK" --query StackDriftDetectionId --output text 2>/dev/null) || { ng "드리프트 탐지 실행 실패"; return; }
  for _ in $(seq 1 30); do s=$(aws cloudformation describe-stack-drift-detection-status --stack-drift-detection-id "$id" --query '[DetectionStatus,StackDriftStatus]' --output text); [[ "$s" == DETECTION_IN_PROGRESS* ]] || break; sleep 3; done
  if [[ "$s" == *IN_SYNC ]]; then ok "드리프트 없음(IN_SYNC)"
  else ng "드리프트: $s — $(aws cloudformation describe-stack-resource-drifts --stack-name "$STACK" --stack-resource-drift-status-filters MODIFIED DELETED --query 'StackResourceDrifts[].[LogicalResourceId,StackResourceDriftStatus]' --output text | tr '\t\n' ': ')"; fi
}
finish() {
  echo "== 결과: PASS $PASS / FAIL $FAIL =="
  if [ "$FAIL" -eq 0 ]; then echo "판정: 정상 (verify 통과) — 기록표에 '복구 완료 시각'과 '통과'를 적으세요"; exit 0
  else echo "판정: 비정상"; exit 1; fi
}
