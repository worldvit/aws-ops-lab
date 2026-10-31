#!/bin/bash
# 앱 서버용 Vault Agent + 내부 HTTPS(8443) 설치 — sec 모듈부터 사용. 여러 번 실행해도 안전하다.
#   VAULT_ADDR=http://<Vault IP>:8200 SECRET_ID=<학번>/sec/app bash sec-agent.sh
# 하는 일
#  1) Vault Agent: 앱 서버 EC2 역할(AWS IAM 인증)로 Vault 에 로그인하고
#     · DB 동적 자격증명(database/creds/app) → /etc/app/db-cred.env (DB_USER, DB_PASSWORD) — 앱이 /db 에서 읽음
#     · 내부 인증서(pki/issue/internal) → /etc/nginx/tls/app.pem — nginx 8443 이 사용
#     · 127.0.0.1:8100 API 프록시 — 앱이 토큰 없이 Transit(암호화) 호출
#  2) nginx: 8443(HTTPS) → 127.0.0.1:8080(앱)
set -euo pipefail
: "${VAULT_ADDR:?VAULT_ADDR 를 지정하세요}" "${SECRET_ID:?SECRET_ID 를 지정하세요}"
command -v vault >/dev/null || {
  dnf install -y dnf-plugins-core
  dnf config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
  dnf install -y vault
}
command -v nginx >/dev/null || dnf install -y nginx
TOKEN=$(curl -s -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)

mkdir -p /etc/vault-agent /etc/nginx/tls /etc/app
cat > /etc/vault-agent/agent.hcl <<EOF
vault { address = "$VAULT_ADDR" }
auto_auth {
  method "aws" {
    config = { type = "iam", role = "app" }
  }
  sink "file" { config = { path = "/etc/vault-agent/token", mode = 0600 } }
}
api_proxy { use_auto_auth_token = true }
listener "tcp" {
  address     = "127.0.0.1:8100"
  tls_disable = true
}
template {
  destination = "/etc/app/db-cred.env"
  perms       = "0644"
  contents    = <<TPL
{{ with secret "database/creds/app" }}DB_USER={{ .Data.username }}
DB_PASSWORD={{ .Data.password }}
DB_LEASE={{ .LeaseID }}
{{ end }}
TPL
}
template {
  destination = "/etc/nginx/tls/app.pem"
  perms       = "0600"
  contents    = <<TPL
{{ with pkiCert "pki/issue/internal" "common_name=app.opslab.internal" "ip_sans=$IP" "ttl=24h" }}{{ .Cert }}{{ .CA }}{{ .Key }}{{ end }}
TPL
  command     = "systemctl reload nginx || systemctl restart nginx || true"
}
EOF

cat > /etc/systemd/system/vault-agent.service <<'EOF'
[Unit]
Description=Vault Agent (opslab app)
After=network-online.target
Wants=network-online.target
[Service]
ExecStart=/usr/bin/vault agent -config=/etc/vault-agent/agent.hcl
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF

cat > /etc/nginx/conf.d/app-tls.conf <<'EOF'
server {
  listen 8443 ssl;
  ssl_certificate     /etc/nginx/tls/app.pem;
  ssl_certificate_key /etc/nginx/tls/app.pem;
  location / { proxy_pass http://127.0.0.1:8080; proxy_set_header Host $host; }
}
EOF
sed -i '/^VAULT_PROXY=/d;/^APP_SECRET_ID=/d' /etc/app/app.env
printf 'VAULT_PROXY=http://127.0.0.1:8100\nAPP_SECRET_ID=%s\n' "$SECRET_ID" >> /etc/app/app.env

systemctl daemon-reload
systemctl enable --now vault-agent
for i in $(seq 1 30); do [ -s /etc/nginx/tls/app.pem ] && break; sleep 2; done   # 첫 인증서 발급 대기
systemctl enable nginx && systemctl restart nginx
systemctl restart app
echo "sec-agent 설치 완료: $(hostname) cert=$([ -s /etc/nginx/tls/app.pem ] && echo ok || echo 없음) cred=$([ -s /etc/app/db-cred.env ] && echo ok || echo 없음)"
