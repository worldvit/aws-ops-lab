#!/bin/bash
# iac ssm-doc — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: SSM 문서 $DOC 에 새 버전 1개를 추가하고 기본 버전으로 지정한다. 앱 서버는 건드리지 않는다.
aws ssm describe-document --name "$DOC" >/dev/null 2>&1 || exit 3
save default_version "$(aws ssm describe-document --name "$DOC" --query Document.DefaultVersion --output text)"
V_=$(pick_variant 2)
case $V_ in
  1) C=$(doc_json app-server 8080) ;;   # 서비스 이름 오타(새 표준 이름이라고 착각)
  2) C=$(doc_json app 8081) ;;         # 헬스 체크 포트 변경(다른 서비스 기준)
esac
NV=$(aws ssm update-document --name "$DOC" --content "$C" --document-version '$LATEST' --query DocumentDescription.DocumentVersion --output text) || exit 1
aws ssm update-document-default-version --name "$DOC" --document-version "$NV" >/dev/null || exit 1
record $V_
