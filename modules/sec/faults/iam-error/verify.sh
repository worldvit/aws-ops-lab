#!/bin/bash
# sec iam-error 판정 — 비밀 읽기, 앱 역할의 인라인 정책. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start iam-error
echo "[1] 앱 기능"; chk_app /secret "비밀 읽기(/secret)"
echo "[2] 앱 역할($APP_ROLE) 인라인 정책"
A=$(aws secretsmanager describe-secret --secret-id "$SECRET_ID" --query ARN --output text 2>/dev/null)
D=$(aws iam get-role-policy --role-name "$APP_ROLE" --policy-name "$APP_POLICY_NAME" --query PolicyDocument --output json 2>/dev/null)
jq -e --arg a "$A" '.Statement[] | select(.Effect=="Allow" and ((.Action|tostring)|contains("secretsmanager:GetSecretValue")) and ((.Resource|tostring)|contains($a)))' <<<"$D" >/dev/null \
  && ok "$APP_POLICY_NAME: 비밀 ARN 에 GetSecretValue 허용" || ng "$APP_POLICY_NAME 이 없거나 비밀 ARN($SECRET_ID)을 허용하지 않음"
n=$(aws iam list-role-policies --role-name "$APP_ROLE" --query 'length(PolicyNames)' --output text)
[ "$n" = 1 ] && ok "인라인 정책 1개(추가 정책 없음)" || ng "인라인 정책 ${n}개 — $(aws iam list-role-policies --role-name "$APP_ROLE" --query PolicyNames --output text)"
finish
