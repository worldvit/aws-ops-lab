#!/bin/bash
# cicd 모듈 1단계 따라하기 명령 모음 — Notion 페이지의 명령과 같다. 따라잡기(start.sh cicd full)도 이 스크립트를 쓴다.
#   source ~/opslab-env.sh && bash ~/opslab/common/start.sh cicd && GITHUB_REPO=<내 GitHub ID>/aws-ops-lab bash ~/opslab/tools/build/cicd.sh
# GitHub 연결 승인(1-2)은 콘솔에서 사람이 한 번 눌러야 한다 — 이 스크립트는 승인될 때까지 기다린다.
set -euo pipefail
source ~/opslab-env.sh
: "${GITHUB_REPO:?GITHUB_REPO=<내 GitHub ID>/aws-ops-lab 형식으로 Fork 한 저장소를 지정하세요}"
TAGS_KV="Key=Course,Value=opslab Key=Module,Value=cicd Key=Owner,Value=$SID"

echo "== 1-2 GitHub 연결(CodeConnections) — 콘솔에서 '보류 중인 연결 업데이트'로 승인"
CONN=$(aws codeconnections list-connections --query "Connections[?ConnectionName=='$SID-cicd-github'].ConnectionArn | [0]" --output text)
if [ -z "$CONN" ] || [ "$CONN" = None ]; then
  CONN=$(aws codeconnections create-connection --provider-type GitHub --connection-name $SID-cicd-github \
    --tags Key=Course,Value=opslab Key=Module,Value=cicd Key=Owner,Value=$SID --query ConnectionArn --output text)
fi
echo "   $CONN"
echo "   콘솔: Developer Tools > 설정 > 연결 > $SID-cicd-github > 보류 중인 연결 업데이트 > GitHub 앱 설치·선택 > 연결"
until [ "$(aws codeconnections get-connection --connection-arn $CONN --query Connection.ConnectionStatus --output text)" = AVAILABLE ]; do
  echo "   … 승인 대기 중 (PENDING) $(date +%T)"; sleep 20; done
echo "   AVAILABLE"

echo "== 1-3 CodeBuild 프로젝트 (빌드·시험·이미지)"
cat > ~/cicd-build.json <<EOF
{
  "name": "$SID-cicd-build",
  "source": { "type": "CODEPIPELINE", "buildspec": "cicd/buildspec.yml" },
  "artifacts": { "type": "CODEPIPELINE" },
  "environment": {
    "type": "LINUX_CONTAINER", "image": "aws/codebuild/amazonlinux-x86_64-standard:5.0",
    "computeType": "BUILD_GENERAL1_SMALL", "privilegedMode": true,
    "environmentVariables": [
      { "name": "SID", "value": "$SID" }, { "name": "ECR_URI", "value": "$ECR_URI" },
      { "name": "EXEC_ROLE_ARN", "value": "$TASK_EXEC_ROLE_ARN" }, { "name": "LOG_GROUP", "value": "$ECS_LOG_GROUP" }
    ]
  },
  "serviceRole": "$BUILD_ROLE_ARN",
  "timeoutInMinutes": 20,
  "tags": [ { "key": "Course", "value": "opslab" }, { "key": "Module", "value": "cicd" }, { "key": "Owner", "value": "$SID" } ]
}
EOF
aws codebuild create-project --cli-input-json file://$HOME/cicd-build.json --query 'project.[name,environment.image]' --output text

echo "== 1-4 CodeDeploy — EC2 Auto Scaling 그룹 롤링(한 대씩, 알람 시 자동 중단·롤백)"
aws deploy create-application --application-name $SID-cicd-ec2 --compute-platform Server --tags $TAGS_KV >/dev/null
aws deploy create-deployment-group --application-name $SID-cicd-ec2 --deployment-group-name $SID-cicd-ec2-dg \
  --service-role-arn $DEPLOY_ROLE_ARN --auto-scaling-groups $SID-cmp-asg \
  --deployment-config-name CodeDeployDefault.OneAtATime \
  --deployment-style deploymentType=IN_PLACE,deploymentOption=WITH_TRAFFIC_CONTROL \
  --load-balancer-info "targetGroupInfoList=[{name=$SID-cmp-tg}]" \
  --auto-rollback-configuration enabled=true,events=DEPLOYMENT_FAILURE,DEPLOYMENT_STOP_ON_ALARM \
  --alarm-configuration "enabled=true,alarms=[{name=$SID-cmp-target-5xx}]" --tags $TAGS_KV --query deploymentGroupId --output text

echo "== 1-5 CodeDeploy — ECS 블루/그린 + 카나리(20% 3분), 알람 시 자동 중단·롤백"
aws deploy create-application --application-name $SID-cicd-ecs --compute-platform ECS --tags $TAGS_KV >/dev/null
aws deploy create-deployment-group --application-name $SID-cicd-ecs --deployment-group-name $SID-cicd-ecs-dg \
  --service-role-arn $DEPLOY_ROLE_ARN --deployment-config-name $SID-cicd-canary20-3m \
  --ecs-services clusterName=$SID-cicd,serviceName=$SID-cicd-svc \
  --deployment-style deploymentType=BLUE_GREEN,deploymentOption=WITH_TRAFFIC_CONTROL \
  --blue-green-deployment-configuration "terminateBlueInstancesOnDeploymentSuccess={action=TERMINATE,terminationWaitTimeInMinutes=1},deploymentReadyOption={actionOnTimeout=CONTINUE_DEPLOYMENT}" \
  --load-balancer-info "targetGroupPairInfoList=[{targetGroups=[{name=$SID-cicd-tg-blue},{name=$SID-cicd-tg-green}],prodTrafficRoute={listenerArns=[$ECS_LISTENER_ARN]}}]" \
  --auto-rollback-configuration enabled=true,events=DEPLOYMENT_FAILURE,DEPLOYMENT_STOP_ON_ALARM \
  --alarm-configuration "enabled=true,alarms=[{name=$SID-cicd-ecs-5xx}]" --tags $TAGS_KV --query deploymentGroupId --output text

echo "== 1-6 파이프라인 만들기 (Source → Build → Release[변경셋·승인·실행] → Deploy[EC2 롤링 ∥ ECS 카나리])"
sed -e "s|__SID__|$SID|g" -e "s|__PIPELINE_ROLE_ARN__|$PIPELINE_ROLE_ARN|g" -e "s|__BUCKET__|$CICD_BUCKET|g" \
    -e "s|__CONNECTION_ARN__|$CONN|g" -e "s|__REPO__|$GITHUB_REPO|g" -e "s|__CFN_ROLE_ARN__|$CFN_ROLE_ARN|g" \
    ~/opslab/modules/cicd/pipeline.tpl.json > ~/cicd-pipeline.json
aws codepipeline create-pipeline --cli-input-json file://$HOME/cicd-pipeline.json --query 'pipeline.[name,pipelineType]' --output text

echo "== 1-7 첫 실행(만들면 자동 시작, 릴리스 v1) — 승인 단계에서 변경셋 확인 후 승인"
CICD_NO_LAB=1 source ~/opslab/modules/cicd/lib.sh
sleep 10
EID=$(aws codepipeline list-pipeline-executions --pipeline-name $PIPE --max-items 1 --query 'pipelineExecutionSummaries[0].pipelineExecutionId' --output text | head -1)
echo "   실행 ID $EID"
R=$(AUTO_APPROVE=1 wait_exec "$EID" 2700); echo "   결과: $R"
[ "$R" = Succeeded ] || { failed_actions "$EID"; exit 1; }

echo "== 1-8 두 번째 릴리스 v2 — EC2 는 한 대씩, ECS 는 20% 카나리 3분 뒤 전체"
EID=$(start_release v2 0); echo "   실행 ID $EID"
R=$(AUTO_APPROVE=1 wait_exec "$EID" 2700); echo "   결과: $R"
[ "$R" = Succeeded ] || { failed_actions "$EID"; exit 1; }
echo "   EC2 :80 → $(ver 80)   ECS :8000 → $(ver 8000)   기록된 릴리스 → $(release)"
