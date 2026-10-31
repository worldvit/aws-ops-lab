#!/bin/bash
# sec 모듈 verify 공통. verify.sh 들이 source 한다.
DATA_NO_LAB=1 source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"
PASS=0; FAIL=0
ok() { echo "  [PASS] $*"; PASS=$((PASS+1)); }
ng() { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }
start() { echo "== $(date '+%F %T') 정상 상태 판정: $SID / sec $1 =="; }
chk_app() {  # $1=경로 $2=이름 — ALB 를 거쳐 5번 모두 status ok
  local ok=0 err="" i b; for i in 1 2 3 4 5; do
    b=$(curl -s -m 8 "http://$(alb_dns)$1"); grep -q '"status":"ok"' <<<"$b" && ok=$((ok+1)) || err=$(jq -r '.message // empty' <<<"$b" 2>/dev/null); done
  [ "$ok" = 5 ] && ok "$2 5/5" || ng "$2 $ok/5 ${err:0:140}"
}
chk_vault() {  # Vault 초기화·잠금 해제 상태
  local s; s=$(ssm_run "$VAULT_ID" "curl -s -m 5 http://127.0.0.1:8200/v1/sys/seal-status" 30)
  if jq -e '.initialized and (.sealed|not)' <<<"$s" >/dev/null 2>&1; then ok "Vault 초기화됨·잠금 해제(unsealed)"
  else ng "Vault 상태: $(jq -c '{initialized,sealed,progress:.progress}' <<<"$s" 2>/dev/null || echo 응답 없음)"; fi
}
chk_tls() {  # loadgen(클라이언트)이 신뢰하는 CA(/etc/opslab/ca.pem)로 앱 서버 8443 호출
  local ips out n t
  ips=$(aws ec2 describe-instances --filters Name=tag:Name,Values="$SID-cmp-app" Name=instance-state-name,Values=running --query 'Reservations[].Instances[].PrivateIpAddress' --output text)
  out=$(ssm_run "$LOADGEN" "for ip in $ips; do c=\$(curl -s -m 5 -o /dev/null -w '%{http_code}' --cacert /etc/opslab/ca.pem https://\$ip:8443/health); [ \"\$c\" = 200 ] && echo \"\$ip 200\" || echo \"\$ip ERR \$(curl -sS -m 5 -o /dev/null --cacert /etc/opslab/ca.pem https://\$ip:8443/health 2>&1 | head -c 120)\"; done" 60)
  t=$(wc -w <<<"$ips"); n=$(grep -c ' 200$' <<<"$out")
  [ "$n" = "$t" ] && [ "$t" -gt 0 ] && ok "내부 HTTPS(8443) 인증서 검증 통과 $n/$t" || ng "내부 HTTPS(8443) $n/$t — $(grep -v ' 200$' <<<"$out" | head -1 | cut -c1-140)"
}
chk_agent() {  # 앱 서버 Vault Agent 동작
  local out t n; out=$(arun "systemctl is-active vault-agent" 30); t=$(wc -w <<<"$(app_ids)"); n=$(grep -c '^active' <<<"$out")
  [ "$n" = "$t" ] && ok "앱 서버 Vault Agent 실행 중 $n/$t" || ng "앱 서버 Vault Agent 실행 중 $n/$t"
}
chk_vpolicy() {  # Vault 앱 정책이 원본과 같은지
  local p; p=$(vrun "vault policy read app" 30)
  local miss=""; for x in database/creds/app pki/issue/internal transit/encrypt/orders transit/decrypt/orders; do grep -q "\"$x\"" <<<"$p" || miss="$miss $x"; done
  [ -z "$miss" ] && ok "Vault 앱 정책(app) 경로 4개 허용" || ng "Vault 앱 정책(app)에 빠진 경로:$miss"
}
finish() {
  echo "== 결과: PASS $PASS / FAIL $FAIL =="
  if [ "$FAIL" -eq 0 ]; then echo "판정: 정상 (verify 통과) — 기록표에 '복구 완료 시각'과 '통과'를 적으세요"; exit 0
  else echo "판정: 비정상"; exit 1; fi
}
