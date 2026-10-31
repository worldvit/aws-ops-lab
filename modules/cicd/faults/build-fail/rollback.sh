#!/bin/bash
# cicd build-fail — rollback. 프로젝트 설정·역할 정책을 정상으로 되돌리고 실패한 실행을 다시 돌린다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
need_pipe
if ! aws iam get-role-policy --role-name "$SID-cicd-build-role" --policy-name ecr-push >/dev/null 2>&1; then
  P=$(load ecr_push); [ -n "$P" ] && [ "$P" != None ] || P="{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"ecr:GetAuthorizationToken\",\"Resource\":\"*\"},{\"Effect\":\"Allow\",\"Action\":[\"ecr:BatchCheckLayerAvailability\",\"ecr:InitiateLayerUpload\",\"ecr:UploadLayerPart\",\"ecr:CompleteLayerUpload\",\"ecr:PutImage\",\"ecr:BatchGetImage\",\"ecr:GetDownloadUrlForLayer\"],\"Resource\":\"arn:aws:ecr:$AWS_REGION:$ACCT:repository/$SID-cicd-app\"}]}"
  aws iam put-role-policy --role-name "$SID-cicd-build-role" --policy-name ecr-push --policy-document "$P" && echo "  빌드 역할 ecr-push 정책 복구"
fi
U=$(aws cloudformation describe-stacks --stack-name "$ENVSTACK" --query "Stacks[0].Outputs[?OutputKey=='EcrUri'].OutputValue" --output text)
aws codebuild update-project --name "$PROJ" --environment "$(aws codebuild batch-get-projects --names "$PROJ" --query 'projects[0].environment' --output json | jq -c --arg u "$U" '.privilegedMode=true | .environmentVariables |= map(if .name=="ECR_URI" then .value=$u else . end)')" >/dev/null && echo "  privilegedMode=true, ECR_URI=$U"
aws codebuild update-project --name "$PROJ" --source type=CODEPIPELINE,buildspec=cicd/buildspec.yml >/dev/null && echo "  buildspec=cicd/buildspec.yml"
sleep 20
E=$(load exec); r=$(retry_exec "$E"); echo "  실행 ${E:0:8} 다시 실행: $r"
[ "$r" = Succeeded ] || { r=$(redeploy_good); echo "  정상 릴리스 재배포: $r"; }
