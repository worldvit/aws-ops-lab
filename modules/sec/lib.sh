#!/bin/bash
# sec 모듈 공통 함수: Vault 서버 명령 실행(vrun), 앱 서버 명령(arun), Vault 앱 정책 원본, KMS·IAM 대상 이름.
# data 모듈 lib.sh(Aurora·loadgen·sql)를 그대로 이어 쓴다. 장애 스크립트는 common/lib.sh 의 SID·LAB 검사를 거친다.
S=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
source "$S/../data/lib.sh"
VAULT_ID=$(inst "$SID-sec-vault")
VAULT_IP=$(aws ec2 describe-instances --instance-ids "$VAULT_ID" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text 2>/dev/null)
V=/opslab/sec/vault
KEY_ALIAS="alias/$SID-sec-key"
SECRET_ID="$SID/sec/app"
APP_ROLE="$SID-base-ec2-role"
APP_POLICY_NAME="$SID-sec-app-access"
# Vault 앱 정책 원본(정상 상태) — 초기화·원복이 같은 내용을 쓴다
APP_VAULT_POLICY='path "database/creds/app"      { capabilities = ["read"] }
path "pki/issue/internal"      { capabilities = ["update"] }
path "transit/encrypt/orders"  { capabilities = ["update"] }
path "transit/decrypt/orders"  { capabilities = ["update"] }'

vrun() {  # $1=Vault 서버에서 실행할 bash 스크립트(VAULT_TOKEN 은 서버가 SSM 에서 직접 읽음) [$2=대기 초]
  local b64; b64=$(printf '%s' "$1" | base64 -w0)
  ssm_run "$VAULT_ID" "export VAULT_ADDR=http://127.0.0.1:8200 AWS_DEFAULT_REGION=$AWS_REGION
export VAULT_TOKEN=\$(aws ssm get-parameter --name $V/root --with-decryption --query Parameter.Value --output text 2>/dev/null)
echo $b64 | base64 -d | bash 2>&1" "${2:-90}"
}
arun() {  # $1=모든 앱 서버에서 실행할 bash 스크립트 [$2=대기 초] → 서버별 출력
  local b64 ids; ids=$(app_ids); [ -n "$ids" ] || return 1
  b64=$(printf '%s' "$1" | base64 -w0)
  ssm_run "$ids" "echo $b64 | base64 -d | bash 2>&1" "${2:-90}"
}
put_app_policy() {  # Vault 앱 정책을 $1 내용으로 덮어쓴다(기본: 원본)
  local b64; b64=$(printf '%s' "${1:-$APP_VAULT_POLICY}" | base64 -w0)
  vrun "echo $b64 | base64 -d | vault policy write app -"
}
vneed() { [ -n "$VAULT_ID" ] && [ "$VAULT_ID" != None ] || { echo "Vault 서버($SID-sec-vault)를 찾지 못했습니다. 1단계 구축을 먼저 끝내세요."; exit 3; }; }
has() {  # 파이프 입력에 $1 이 있는지 — 'cmd | grep -q' 는 pipefail 에서 앞 명령이 SIGPIPE 로 끝나 거짓 실패가 나므로 다 받은 뒤 검사
  local o; o=$(cat); grep -qi -- "$1" <<<"$o"
}
