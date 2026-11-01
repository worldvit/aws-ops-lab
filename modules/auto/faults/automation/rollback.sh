#!/bin/bash
# auto automation — rollback. 역할 정책·안전 스위치를 원본으로, 런북은 대상 태그가 맞는 버전을 기본으로(없으면 원본 내용으로 새 버전).
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
put_auto_policy && echo "  자동화 역할 정책 원본"
aws ssm put-parameter --name "$SWITCH" --type String --value on --overwrite >/dev/null && echo "  안전 스위치 on"
for v in $(aws ssm list-document-versions --name "$RUNBOOK" --query 'DocumentVersions[].DocumentVersion' --output text); do
  t=$(aws ssm get-document --name "$RUNBOOK" --document-version "$v" --document-format JSON --query Content --output text | jq -r '.parameters.TagValue.default')
  [ "$t" = "$APP_TAG" ] && { aws ssm update-document-default-version --name "$RUNBOOK" --document-version "$v" >/dev/null && echo "  런북 기본 버전 → $v"; exit 0; }
done
NV=$(aws ssm update-document --name "$RUNBOOK" --document-format YAML --content "$(runbook_content)" --document-version '$LATEST' --query DocumentDescription.DocumentVersion --output text)
aws ssm update-document-default-version --name "$RUNBOOK" --document-version "$NV" >/dev/null && echo "  원본 내용으로 새 버전 $NV → 기본"
