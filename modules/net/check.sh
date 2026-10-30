#!/bin/bash
# net 모듈 verify 공통: 경로 점검 결과와 지표로 판정한다. verify.sh 들이 source 한다.
NET_NO_LAB=1 source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"
PASS=0; FAIL=0
ok() { echo "  [PASS] $*"; PASS=$((PASS+1)); }
ng() { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }
start() { echo "== $(date '+%F %T') 정상 상태 판정: $SID / net $1 =="; OUT=$(probe_raw); }
v() { sed -n "s/^$1=//p" <<<"$OUT" | head -1; }

chk_user() { [ "$(v user_alb)" = 5/5 ] && ok "① 사용자 → ALB 5/5" || ng "① 사용자 → ALB $(v user_alb)"; }
chk_nat() {
  local n=0 k r
  while IFS='=' read -r k r; do n=$((n+1))
    [ "$r" = 5/5 ] && ok "② loadgen → ALB ${k#nat_alb_} (NAT) 5/5" || ng "② loadgen → ALB ${k#nat_alb_} (NAT) $r"
  done < <(grep '^nat_alb_' <<<"$OUT")
  [ "$n" -gt 0 ] || ng "② loadgen 점검 결과 없음"
}
chk_tgw() { local t; t=$(v tgw_svc); [ "${t%% *}" = 5/5 ] && ok "③ loadgen → 내부 서비스 (TGW) 5/5" || ng "③ loadgen → 내부 서비스 (TGW) ${t:-결과 없음}"; }
chk_sts() {
  local d c; d=$(v sts_dns); c=$(v sts_call)
  case "$d" in 10.20.*) ok "④ STS 이름 해석: 사설 IP $d (엔드포인트)";; *) ng "④ STS 이름 해석: ${d:-결과 없음} (사설 IP 10.20.x 여야 함)";; esac
  [ "$c" = ok ] && ok "④ 내부 서비스 → STS 호출 성공" || ng "④ 내부 서비스 → STS 호출: ${c:-결과 없음}"
}
chk_natmetric() {  # 인자 없음: 가장 최근 1분 값이 0인지 / 인자 N: 최근 N분 합계가 0인지 (지표는 1~2분 늦게 나온다)
  local m q='sum(Datapoints[].Sum)' w=${1:-5} lbl="최근 ${1:-5}분"
  [ -z "${1:-}" ] && { q='sort_by(Datapoints,&Timestamp)[-1].Sum'; lbl="가장 최근 1분"; }
  m=$(aws cloudwatch get-metric-statistics --namespace AWS/NATGateway --metric-name ErrorPortAllocation \
    --dimensions Name=NatGatewayId,Value="$NAT" --start-time "$(date -u -d "-$w min" +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" \
    --period 60 --statistics Sum --query "$q" --output text 2>/dev/null | sed 's/None/0/')
  [ "${m%.*}" -eq 0 ] && ok "NAT ErrorPortAllocation $lbl 0건" || ng "NAT ErrorPortAllocation $lbl ${m%.*}건 (멈춘 뒤 1~2분은 남아 있을 수 있음)"
}
finish() {
  echo "== 결과: PASS $PASS / FAIL $FAIL =="
  if [ "$FAIL" -eq 0 ]; then echo "판정: 정상 (verify 통과) — 기록표에 '복구 완료 시각'과 '통과'를 적으세요"; exit 0
  else echo "판정: 비정상"; exit 1; fi
}
