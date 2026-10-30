#!/bin/bash
# 경로 점검 도구 — 네 갈래 통신 경로가 지금 되는지 한 표로 본다. 실행 위치: CloudShell (약 30초)
#   bash ~/opslab/modules/net/probe.sh
# ① 사용자 → ALB          (인터넷 → ALB → 앱 서버)
# ② loadgen → ALB 공인 IP  (앱 서브넷 → NAT Gateway → 인터넷 → ALB), ALB IP마다 따로
# ③ loadgen → 내부 서비스   (기반 VPC → Transit Gateway → 방화벽 → 사내 서비스 VPC)
# ④ 내부 서비스 → STS       (사내 서비스 VPC → 인터페이스 엔드포인트(PrivateLink) → STS)
# 증상만 보여 준다. 원인은 경로 위의 구성 요소를 하나씩 확인해 찾는다.
NET_NO_LAB=1 source "$(dirname "$(readlink -f "$0")")/lib.sh"
mark() { case "$1" in 5/5) echo "✅";; 0/5) echo "❌";; *) echo "⚠️ ";; esac; }

echo "== $(date '+%F %T') 경로 점검: $SID =="
OUT=$(probe_raw)
v() { sed -n "s/^$1=//p" <<<"$OUT" | head -1; }
u=$(v user_alb);  printf '%s ① 사용자 → ALB                       %s 성공\n' "$(mark "$u")" "$u"
while IFS='=' read -r k r; do
  printf '%s ② loadgen → ALB %-15s (NAT)   %s 성공\n' "$(mark "$r")" "${k#nat_alb_}" "$r"
done < <(grep '^nat_alb_' <<<"$OUT")
grep -q '^nat_alb_' <<<"$OUT" || echo "❓ ② loadgen 점검 결과 없음 (loadgen 실행 중인지 확인)"
t=$(v tgw_svc); [ -n "$t" ] && printf '%s ③ loadgen → 내부 서비스 %s:8080 (TGW)  %s\n' "$(mark "${t%% *}")" "$SVC_IP" "$t"
d=$(v sts_dns); c=$(v sts_call)
if [ -n "$d" ]; then
  case "$d" in 10.20.*) dn="사설 IP $d";; none) dn="해석 실패";; *) dn="공인 IP $d";; esac
  [ "$c" = ok ] && m="✅" || m="❌"
  printf '%s ④ 내부 서비스 → STS (PrivateLink)       이름 해석: %s / 호출: %s\n' "$m" "$dn" "$c"
else
  echo "❓ ④ 내부 서비스 점검 결과 없음 (서버가 SSM에 연결되어 있는지 확인)"
fi
echo "(✅ 정상  ⚠️ 일부 실패  ❌ 전부 실패)"
