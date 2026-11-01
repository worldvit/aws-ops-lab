#!/bin/bash
# sec iam-error — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: 앱 역할($APP_ROLE)의 인라인 정책만($APP_POLICY_NAME 수정·삭제, $SID-sec-guardrail 추가). 관리형 정책은 건드리지 않는다.
D_=$(aws iam get-role-policy --role-name "$APP_ROLE" --policy-name "$APP_POLICY_NAME" --query PolicyDocument --output json) || exit 3
save doc "$(jq -c . <<<"$D_")"
V_=$(pick_variant 3)
case $V_ in
  1) aws iam delete-role-policy --role-name "$APP_ROLE" --policy-name "$APP_POLICY_NAME" ;;
  2) aws iam put-role-policy --role-name "$APP_ROLE" --policy-name "$SID-sec-guardrail" --policy-document \
       '{"Version":"2012-10-17","Statement":[{"Sid":"DenySecretsOutsideVpce","Effect":"Deny","Action":"secretsmanager:GetSecretValue","Resource":"*","Condition":{"StringNotEquals":{"aws:SourceVpce":"vpce-00000000"}}}]}' ;;
  3) # 비밀 ARN 의 이름을 …/app → …/app-prod 로(모든 문장, Resource 가 문자열이든 배열이든 — 콘솔 시각 편집기로 만든 정책 대비)
     N_=$(jq -c 'def f: sub("secret:(?<n>[^:]*)/app"; "secret:\(.n)/app-prod");
                 .Statement |= (if type=="array" then . else [.] end | map(if .Resource then .Resource |= (if type=="array" then map(f) else f end) else . end))' <<<"$D_") || exit 1
     if [ "$(jq -cS . <<<"$N_")" = "$(jq -cS '.Statement |= (if type=="array" then . else [.] end)' <<<"$D_")" ]; then   # 와일드카드 등으로 바뀐 곳이 없으면 GetSecretValue 허용 문장의 대상을 틀린 비밀로 고정
       B_=$(aws secretsmanager describe-secret --secret-id "$SECRET_ID" --query ARN --output text | sed -E 's#(secret:[^:]*)/app#\1/app-prod#')
       N_=$(jq -c --arg b "$B_" '.Statement |= (if type=="array" then . else [.] end | map(if .Effect=="Allow" and ((.Action|tostring)|contains("GetSecretValue")) then .Resource=$b else . end))' <<<"$D_")
     fi
     aws iam put-role-policy --role-name "$APP_ROLE" --policy-name "$APP_POLICY_NAME" --policy-document "$N_" ;;
esac || exit 1
record $V_
