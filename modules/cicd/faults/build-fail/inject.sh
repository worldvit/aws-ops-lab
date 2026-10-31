#!/bin/bash
# cicd build-fail — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: CodeBuild 프로젝트  설정 또는 빌드 역할 인라인 정책 하나, 새 릴리스 실행 1회. 서비스는 이전 버전 유지.
need_pipe
V_=$(pick_variant 3)
case $V_ in
  1) aws iam get-role-policy --role-name "$SID-cicd-build-role" --policy-name ecr-push --query PolicyDocument --output json > /tmp/ecr-push.json &&
     save ecr_push "$(jq -c . /tmp/ecr-push.json)" &&
     aws iam delete-role-policy --role-name "$SID-cicd-build-role" --policy-name ecr-push ;;
  2) # 프로젝트 환경변수 ECR_URI 를 없는 저장소로(이미지 푸시 실패)
     aws codebuild update-project --name "$PROJ" --environment "$(aws codebuild batch-get-projects --names "$PROJ" --query 'projects[0].environment' --output json | jq -c '.environmentVariables |= map(if .name=="ECR_URI" then .value=(.value+"-prod") else . end)')" >/dev/null ;;
  3) aws codebuild update-project --name "$PROJ" --source type=CODEPIPELINE,buildspec=cicd/buildspec-prod.yml >/dev/null ;;
esac || exit 1
sleep 10
E=$(start_release "$(new_ver)" 0) || exit 1; save exec "$E"
[ "$(wait_exec "$E" 900)" = Failed ] || exit 1
record $V_
