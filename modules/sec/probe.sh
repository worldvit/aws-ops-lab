#!/bin/bash
# 시크릿 점검 도구 — 앱 기능(증상)과 비밀 공급 경로(Vault·Agent·인증서·KMS·IAM)를 한 화면에 본다. 실행 위치: CloudShell (약 40초)
#   bash ~/opslab/modules/sec/probe.sh
# 원인은 알려 주지 않는다. "어디가 이상한가"까지만 보여 준다 — 원인은 로그·이벤트·CloudTrail 로 찾는다.
DATA_NO_LAB=1 source "$(dirname "$(readlink -f "$0")")/lib.sh"
DNS=$(alb_dns)
echo "== $(date '+%F %T') 시크릿 점검: $SID (Vault $VAULT_IP) =="
try() {  # $1=경로 → "성공수/5 마지막오류"
  local ok=0 err="" i body
  for i in 1 2 3 4 5; do
    body=$(curl -s -m 8 "http://$DNS$1"); grep -q '"status":"ok"' <<<"$body" && ok=$((ok+1)) || err=$(jq -r '.message // empty' <<<"$body" 2>/dev/null)
  done; echo "$ok/5 ${err:0:120}"
}
m() { case "$1" in 5/5*) echo "✅";; 0/5*) echo "❌";; *) echo "⚠️ ";; esac; }
a=$(try /db); b=$(try /note); c=$(try /secret)
echo "[증상] 앱 기능 (ALB 경유)"
printf '  %s ① DB 쓰기 (/db)         %s\n' "$(m "$a")" "$a"
printf '  %s ② 메모 (/note)          %s\n' "$(m "$b")" "$b"
printf '  %s ③ 비밀 읽기 (/secret)   %s\n' "$(m "$c")" "$c"
echo "[공급 경로]"
s=$(ssm_run "$VAULT_ID" "curl -s -m 5 http://127.0.0.1:8200/v1/sys/seal-status" 30)
echo "  ④ Vault: $(jq -r '"initialized=\(.initialized) sealed=\(.sealed) 잠금해제 진행=\(.progress)/\(.t)"' <<<"$s" 2>/dev/null || echo '응답 없음')"
echo "  ⑤ 앱 서버(Agent·DB 자격증명·인증서 만료):"
arun "echo \"    \$(hostname -s) agent=\$(systemctl is-active vault-agent) db_user=\$(grep -oP '^DB_USER=\K.*' /etc/app/db-cred.env 2>/dev/null | cut -c1-28) cert_until=\$(openssl x509 -in /etc/nginx/tls/app.pem -noout -enddate 2>/dev/null | cut -d= -f2)\"" 40
ips=$(aws ec2 describe-instances --filters Name=tag:Name,Values="$SID-cmp-app" Name=instance-state-name,Values=running --query 'Reservations[].Instances[].PrivateIpAddress' --output text)
echo "  ⑥ 내부 HTTPS 8443 (loadgen 이 신뢰하는 CA 로 검증):"
ssm_run "$LOADGEN" "for ip in $ips; do r=\$(curl -sS -m 5 -o /dev/null -w '%{http_code}' --cacert /etc/opslab/ca.pem https://\$ip:8443/health 2>&1); echo \"    \$ip \${r:0:110}\"; done" 40
echo "(✅ 정상  ⚠️ 일부 실패  ❌ 전부 실패)"
