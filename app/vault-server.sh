#!/bin/bash
# Vault 서버 설치 — Vault EC2(<학번>-sec-vault)의 사용자 데이터에서 실행된다. 여러 번 실행해도 안전하다.
# 단일 노드, 파일 스토리지(/opt/vault/data), 내부망 HTTP 8200(실습용 — 운영에서는 TLS 필수).
# 초기화(operator init)·잠금 해제(unseal)는 하지 않는다 → layers/l4-secret.init.sh 또는 수강생이 직접.
set -euo pipefail
dnf install -y dnf-plugins-core jq
dnf config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
dnf install -y vault
mkdir -p /opt/vault/data && chown -R vault:vault /opt/vault
IP=$(TOKEN=$(curl -s -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 60"); \
     curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
cat > /etc/vault.d/vault.hcl <<EOF
ui            = true
disable_mlock = true
storage "file" {
  path = "/opt/vault/data"
}
listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}
api_addr = "http://$IP:8200"
EOF
echo 'export VAULT_ADDR=http://127.0.0.1:8200' > /etc/profile.d/vault.sh
systemctl enable --now vault
