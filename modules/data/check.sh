#!/bin/bash
# data 모듈 verify 공통. verify.sh 들이 source 한다.
DATA_NO_LAB=1 source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"
PASS=0; FAIL=0
ok() { echo "  [PASS] $*"; PASS=$((PASS+1)); }
ng() { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }
start() { echo "== $(date '+%F %T') 정상 상태 판정: $SID / data $1 =="; }
chk_app() {  # $1=경로 $2=이름 — ALB 를 거쳐 5번 모두 status ok
  local ok=0 err="" i b; for i in 1 2 3 4 5; do
    b=$(curl -s -m 6 "http://$(alb_dns)$1"); grep -q '"status":"ok"' <<<"$b" && ok=$((ok+1)) || err=$(jq -r '.message // empty' <<<"$b" 2>/dev/null); done
  [ "$ok" = 5 ] && ok "$2 5/5" || ng "$2 $ok/5 ${err:0:100}"
}
chk_cluster() {
  [ "$DB_STATUS" = available ] && ok "클러스터 상태 available" || ng "클러스터 상태 ${DB_STATUS:-없음}"
  local h; h=$(pget host); [ "$h" = "$WRITER_EP" ] && ok "앱 설정 host = 클러스터(라이터) 엔드포인트" || ng "앱 설정 host = ${h:-없음} (클러스터 엔드포인트 $WRITER_EP 여야 함)"
}
chk_jobs() {  # $@=작업 이름 — loadgen 에서 실행 중이면 FAIL (배경 작업이 연결·부하를 만드는 장애)
  local j; j=$(ssm_run "$LOADGEN" "for u in $*; do systemctl is-active -q \$u && echo -n \"\$u \"; done; true" 30)
  [ -z "${j// /}" ] && ok "loadgen 배경 작업 없음 ($*)" || ng "loadgen 배경 작업 실행 중: $j"
}
finish() {
  echo "== 결과: PASS $PASS / FAIL $FAIL =="
  if [ "$FAIL" -eq 0 ]; then echo "판정: 정상 (verify 통과) — 기록표에 '복구 완료 시각'과 '통과'를 적으세요"; exit 0
  else echo "판정: 비정상"; exit 1; fi
}
