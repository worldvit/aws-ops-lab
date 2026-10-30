#!/bin/bash
# 모듈 독립 시험 (강사·작성자용) — 과정에 넣기 전에 모듈이 혼자서 동작하는지 확인한다.
#   SID=s00 bash ~/opslab/tools/test-module.sh cmp
# 순서: 정리 → 환경 층 배포(builds 층까지 + 모듈 env/done) → baseline verify → 모든 Lab·모든 변형 주입→원복 → 정리
#   DEEP=<초> 이면 주입 후·원복 후 그 초만큼 기다려 장애 verify 가 각각 실패·통과하는지도 본다(증상 검증).
#   SKIP_START=1 이면 앞의 정리·배포를 건너뛰고 지금 환경으로 시험한다(따라하기 명령 검증용).
# 계정에 L0 층(<학번>-l0)이 있어야 한다. 부하 도구는 돌리지 않으므로 "요청 수 0건" FAIL 은 무시한다.
set -uo pipefail
: "${SID:?SID 를 지정하세요. 예) SID=s00 bash tools/test-module.sh cmp}"
export AWS_REGION="${AWS_REGION:-ap-northeast-2}" SID
ROOT=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
MOD=${1:?모듈 ID}; MY="$ROOT/modules/$MOD/module.yaml"
[ -f "$MY" ] || { echo "모듈 없음: $MOD"; exit 1; }
LOG=~/test-$MOD-$(date +%m%d-%H%M).log; FAILS=0
say() { echo "$*" | tee -a "$LOG"; }
judge() {  # verify 출력에서 '요청 수 0건' 외 FAIL 개수
  grep '\[FAIL\]' | grep -vc '요청 수 0건' || true
}

say "== $(date '+%F %T') 모듈 시험: $MOD ($SID)"
if [ -z "${SKIP_START:-}" ]; then   # SKIP_START=1: 이미 구축한 환경(예: 따라하기 명령으로 직접 구축)을 그대로 시험
  echo "$SID" | bash "$ROOT/common/cleanup.sh" >>"$LOG" 2>&1
  bash "$ROOT/common/start.sh" "$MOD" full 2>&1 | tee -a "$LOG" | tail -1
  say "-- 앱 기동 대기 3분"; sleep 180
fi

n=$(bash "$ROOT/modules/$MOD/baseline/verify.sh" 2>&1 | tee -a "$LOG" | judge)
say "baseline verify: FAIL ${n} (요청 수 제외)"; [ "$n" -eq 0 ] || FAILS=$((FAILS+1))

grep -E '^ *- *[a-z]+-[0-9]+ *\|' "$MY" | while IFS='|' read -r lab fault vars level type; do
  lab=$(sed 's/^ *- *//' <<<"$lab" | xargs)
  vars=$(xargs <<<"$vars"); fault=$(xargs <<<"$fault")
  for v in $(seq 1 "$vars"); do
    r=$(VARIANT=$v bash "$ROOT/common/inject.sh" "$lab" </dev/null 2>&1 | grep -c '✅')
    d=""; if [ -n "${DEEP:-}" ] && [ "$r" -ge 1 ]; then   # DEEP=1: 주입 후 verify 가 실패하는지(증상이 나는지)
      sleep "$DEEP"; bash "$ROOT/modules/$MOD/faults/$fault/verify.sh" >>"$LOG" 2>&1 && d=" 증상=없음!" || d=" 증상=있음"; fi
    b=$(echo y | bash "$ROOT/common/inject.sh" rollback "$lab" 2>&1 | grep -c '✅ 원복')
    if [ -n "${DEEP:-}" ] && [ "$b" -ge 1 ]; then          # 원복 후 verify 가 통과하는지
      sleep "$DEEP"; bash "$ROOT/modules/$MOD/faults/$fault/verify.sh" >>"$LOG" 2>&1 && d="$d 원복판정=통과" || d="$d 원복판정=실패!"; fi
    [ "$r" -ge 1 ] && [ "$b" -ge 1 ] && [[ "$d" != *"!"* ]] && res=OK || { res=XX; echo FAIL >> "$LOG.fail"; }
    say "$res $lab v$v ($fault) 주입=$r 원복=$b$d"
  done
done
[ -f "$LOG.fail" ] && FAILS=$((FAILS + $(wc -l < "$LOG.fail"))) && rm -f "$LOG.fail"

say "-- 원복 후 판정 대기 2분"; sleep 120
n=$(bash "$ROOT/modules/$MOD/baseline/verify.sh" 2>&1 | tee -a "$LOG" | judge)
say "원복 후 baseline verify: FAIL ${n} (요청 수 제외)"; [ "$n" -eq 0 ] || FAILS=$((FAILS+1))

echo "$SID" | bash "$ROOT/common/cleanup.sh" >>"$LOG" 2>&1
say "== 결과: 실패 $FAILS 건 (상세 로그 $LOG)"
[ "$FAILS" -eq 0 ]
