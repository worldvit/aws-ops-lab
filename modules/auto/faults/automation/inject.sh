#!/bin/bash
# auto automation — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: 자동화 역할의 인라인 정책(v1), 안전 스위치 매개변수(v2), 런북 문서의 새 버전(v3) 중 하나. 앱 서버는 건드리지 않는다.
aws ssm describe-document --name "$RUNBOOK" >/dev/null 2>&1 || exit 3
save default_version "$(aws ssm describe-document --name "$RUNBOOK" --query Document.DefaultVersion --output text)"
V_=$(pick_variant 3)
case $V_ in
  1) # 권한 정리 중 자동화 역할에서 명령 실행 권한(ssm:SendCommand)이 빠짐
     P=$(aws iam get-role-policy --role-name "$SID-auto-automation-role" --policy-name automation --query PolicyDocument --output json) || exit 1
     aws iam put-role-policy --role-name "$SID-auto-automation-role" --policy-name automation        --policy-document "$(jq -c '.Statement |= map(if .Sid=="RunCommand" then .Action |= map(select(. != "ssm:SendCommand")) else . end)' <<<"$P")" || exit 1 ;;
  2) # 점검 때 안전 스위치를 off 로 내려 두고 잊음
     aws ssm put-parameter --name "$SWITCH" --value off --overwrite >/dev/null || exit 1 ;;
  3) # 문서를 고치다 대상 태그 기본값에 오타(…-cmp-api)가 들어간 새 버전이 기본 버전이 됨
     NV=$(aws ssm update-document --name "$RUNBOOK" --document-format YAML --content "$(runbook_content | sed "s|default: $APP_TAG|default: $SID-cmp-api|")"           --document-version '$LATEST' --query DocumentDescription.DocumentVersion --output text) || exit 1
     aws ssm update-document-default-version --name "$RUNBOOK" --document-version "$NV" >/dev/null || exit 1 ;;
esac
record $V_
