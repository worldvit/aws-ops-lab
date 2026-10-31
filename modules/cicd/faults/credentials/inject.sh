#!/bin/bash
# cicd credentials — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: 파이프라인 역할(<학번>-cicd-pipeline-role)에 거부 정책 1개, 새 릴리스 실행 1회. 서비스는 이전 버전 유지.
need_pipe
V_=$(pick_variant 2)
case $V_ in
  1) put_deny "$SID-cicd-pipeline-role" '["codestar-connections:UseConnection","codeconnections:UseConnection"]' ;;
  2) put_deny "$SID-cicd-pipeline-role" '["codebuild:StartBuild"]' ;;
esac || exit 1
sleep 20
E=$(start_release "$(new_ver)" 0) || exit 1; save exec "$E"
[ "$(wait_exec "$E" 900)" = Failed ] || exit 1
record $V_
