#!/bin/bash
# L4 층 초기화 — Vault 초기화·잠금 해제·엔진 설정, notes 테이블, 앱 서버 Vault Agent 설치. 여러 번 실행해도 안전하다.
# common/start.sh 가 L4 층 배포 뒤 자동으로 부른다. 수강생은 sec 모듈 1단계에서 단계별로 직접 실행한다(tools/build/sec.sh).
#   bash ~/opslab/layers/l4-secret.init.sh
set -uo pipefail
DATA_NO_LAB=1 source "$(dirname "$(readlink -f "$0")")/../modules/sec/lib.sh"
need WRITER_EP ADMIN_PW LOADGEN; vneed
ACCT=$(aws sts get-caller-identity --query Account --output text)

echo "== 1) Vault 서버 설치 대기 ($VAULT_ID, $VAULT_IP)"
ssm_run "$VAULT_ID" "for i in \$(seq 1 90); do systemctl is-active -q vault && break; sleep 5; done; systemctl is-active vault" 480

echo "== 2) 초기화(operator init — 키 조각 3개, 잠금 해제에 2개 필요)"
if vrun 'vault status -format=json | jq -r .initialized' | grep -q false; then
  J=$(vrun 'vault operator init -key-shares=3 -key-threshold=2 -format=json')
  jq -e .root_token <<<"$J" >/dev/null || { echo "초기화 실패: $J"; exit 1; }
  for n in 0 1 2; do
    aws ssm put-parameter --name "$V/unseal-$((n+1))" --type SecureString --overwrite --value "$(jq -r ".unseal_keys_b64[$n]" <<<"$J")" >/dev/null
  done
  aws ssm put-parameter --name "$V/root" --type SecureString --overwrite --value "$(jq -r .root_token <<<"$J")" >/dev/null
  echo "  키 조각 3개와 root 토큰을 SSM $V/* (SecureString)에 보관"
else
  echo "  이미 초기화됨"
fi

echo "== 3) 잠금 해제(unseal — 키 조각 2개)"
vrun "for n in 1 2; do vault operator unseal \$(aws ssm get-parameter --name $V/unseal-\$n --with-decryption --query Parameter.Value --output text) >/dev/null; done
vault status | grep -E '^(Sealed|Initialized)'"

echo "== 4) 인증·엔진·정책 설정"
put_app_policy
vrun "set -e
vault auth list | grep -q '^aws/' || vault auth enable aws
vault write auth/aws/role/app auth_type=iam bound_iam_principal_arn=arn:aws:iam::$ACCT:role/$SID-base-ec2-role \
  resolve_aws_unique_ids=false token_policies=app token_ttl=1h token_max_ttl=24h >/dev/null
vault secrets list | grep -q '^database/' || vault secrets enable database
vault write database/config/opslab plugin_name=postgresql-database-plugin allowed_roles=app \
  connection_url='postgresql://{{username}}:{{password}}@$WRITER_EP:5432/opslab' username=opslab_admin password='$ADMIN_PW' >/dev/null
vault write database/roles/app db_name=opslab default_ttl=1h max_ttl=24h \
  creation_statements=\"CREATE ROLE \\\"{{name}}\\\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}' IN ROLE app;\" \
  revocation_statements=\"DROP ROLE IF EXISTS \\\"{{name}}\\\";\" >/dev/null
vault secrets list | grep -q '^pki/' || { vault secrets enable pki; vault secrets tune -max-lease-ttl=87600h pki; }
vault list pki/issuers >/dev/null 2>&1 || vault write -field=issuer_id pki/root/generate/internal common_name='opslab internal CA' issuer_name=root-1 ttl=87600h >/dev/null
vault write pki/roles/internal allow_any_name=true allow_ip_sans=true max_ttl=72h >/dev/null
vault secrets list | grep -q '^transit/' || vault secrets enable transit
vault read transit/keys/orders >/dev/null 2>&1 || vault write -f transit/keys/orders >/dev/null
vault secrets list | awk 'NR>2{print \$1}' | tr '\n' ' '; echo; vault auth list | awk 'NR>2{print \$1}' | tr '\n' ' '; echo"

echo "== 5) notes 테이블과 첫 메모(키 버전 1로 암호화)"
sql "CREATE TABLE IF NOT EXISTS notes (id serial PRIMARY KEY, ct text NOT NULL, at timestamptz DEFAULT now()); ALTER TABLE notes OWNER TO app;" >/dev/null
if [ "$(sql 'SELECT count(*) FROM notes;' | tr -dc 0-9)" = 0 ]; then
  CT=$(vrun "vault write -field=ciphertext transit/encrypt/orders plaintext=\$(printf 'first order note' | base64)" | grep '^vault:v' | head -1)
  [ -n "$CT" ] && sql "INSERT INTO notes(ct) VALUES ('$CT');" >/dev/null && echo "  첫 메모 저장: ${CT:0:20}…"
fi

echo "== 6) 클라이언트(loadgen)에 내부 CA 배포 — 8443 호출 시 이 CA 로 인증서를 검증한다"
ssm_run "$LOADGEN" "mkdir -p /etc/opslab && curl -s -m 5 http://$VAULT_IP:8200/v1/pki/ca/pem -o /etc/opslab/ca.pem && grep -c BEGIN /etc/opslab/ca.pem" 30

echo "== 7) 앱 서버 Vault Agent·내부 HTTPS(8443) 설치"
aws ssm put-parameter --name "$V/addr" --type String --overwrite --value "http://$VAULT_IP:8200" >/dev/null
aws ssm put-parameter --name /opslab/sec/secret_id --type String --overwrite --value "$SID/sec/app" >/dev/null
IDS=$(app_ids)
[ -n "$IDS" ] && ssm_run "$IDS" "curl -fsSL https://raw.githubusercontent.com/worldvit/aws-ops-lab/main/app/sec-agent.sh | VAULT_ADDR=http://$VAULT_IP:8200 SECRET_ID=$SID/sec/app bash 2>&1 | tail -1" 300
echo "✅ L4 초기화 완료 (Vault: http://$VAULT_IP:8200)"
