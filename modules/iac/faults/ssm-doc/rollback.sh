#!/bin/bash
# iac ssm-doc — rollback. 정상 내용의 버전을 기본 버전으로 되돌린다(없으면 원본 내용으로 새 버전).
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
G=$(doc_json app 8080 | jq -S -c .)
for v in $(aws ssm list-document-versions --name "$DOC" --query 'DocumentVersions[].DocumentVersion' --output text); do
  c=$(aws ssm get-document --name "$DOC" --document-version "$v" --query Content --output text | jq -S -c . 2>/dev/null)
  [ "$c" = "$G" ] && { aws ssm update-document-default-version --name "$DOC" --document-version "$v" >/dev/null && echo "  기본 버전 → $v"; exit 0; }
done
NV=$(aws ssm update-document --name "$DOC" --content "$(doc_json app 8080)" --document-version '$LATEST' --query DocumentDescription.DocumentVersion --output text)
aws ssm update-document-default-version --name "$DOC" --document-version "$NV" >/dev/null && echo "  원본 내용으로 새 버전 $NV → 기본"
