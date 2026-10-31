#!/bin/bash
# sec kms-policy 판정 — 비밀 읽기, 키 정책의 앱 문장. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start kms-policy
echo "[1] 앱 기능"; chk_app /secret "비밀 읽기(/secret)"
echo "[2] KMS 키 정책 ($KEY_ALIAS)"
K=$(aws kms describe-key --key-id "$KEY_ALIAS" --query KeyMetadata.KeyId --output text 2>/dev/null)   # get-key-policy 는 별칭을 받지 않는다
P=$(aws kms get-key-policy --key-id "$K" --policy-name default --query Policy --output text 2>/dev/null)
jq -e --arg r ":role/$APP_ROLE" '.Statement[] | select(.Effect=="Allow" and ((.Principal.AWS|tostring)|endswith($r)) and ((.Action|tostring)|contains("kms:Decrypt")))' <<<"$P" >/dev/null \
  && ok "앱 역할 복호화 허용 문장 있음" || ng "앱 역할($APP_ROLE) 복호화 허용 문장 없음"
d=$(jq -r '[.Statement[] | select(.Effect=="Deny")] | length' <<<"$P" 2>/dev/null)
[ "${d:-1}" = 0 ] && ok "거부(Deny) 문장 없음" || ng "거부(Deny) 문장 ${d}개"
finish
