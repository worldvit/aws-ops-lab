#!/bin/bash
# iac 모듈 1단계 따라하기 명령 모음 — Notion 페이지의 명령과 같다. 따라잡기(start.sh iac full)도 이 스크립트를 쓴다.
#   source ~/opslab-env.sh && bash ~/opslab/common/start.sh iac && bash ~/opslab/tools/build/iac.sh
set -euo pipefail
source ~/opslab-env.sh
ACCT=$(aws sts get-caller-identity --query Account --output text)
T=~/opslab/modules/iac/iac-app.yaml

echo "== 1-2 외부 의존 설정(사전 점검이 읽는 값)"
aws ssm put-parameter --name /opslab/iac/dependency --type String --overwrite --value ready >/dev/null

echo "== 1-3 변경셋으로 검토한 뒤 스택 생성"
aws cloudformation create-change-set --stack-name $SID-iac-app --change-set-name initial --change-set-type CREATE \
  --template-body file://$T --parameters ParameterKey=StudentId,ParameterValue=$SID \
  --capabilities CAPABILITY_NAMED_IAM --tags Key=Course,Value=opslab Key=Module,Value=iac Key=Owner,Value=$SID >/dev/null
aws cloudformation wait change-set-create-complete --stack-name $SID-iac-app --change-set-name initial
aws cloudformation describe-change-set --stack-name $SID-iac-app --change-set-name initial \
  --query 'Changes[].ResourceChange.[Action,LogicalResourceId,ResourceType]' --output table
aws cloudformation execute-change-set --stack-name $SID-iac-app --change-set-name initial
aws cloudformation wait stack-create-complete --stack-name $SID-iac-app
aws cloudformation describe-stacks --stack-name $SID-iac-app --query 'Stacks[0].Outputs' --output table

echo "== 1-4 배포 산출물과 허용 릴리스 목록"
B=$(aws cloudformation describe-stacks --stack-name $SID-iac-app --query "Stacks[0].Outputs[?OutputKey=='ArtifactBucket'].OutputValue" --output text)
echo "app build $(date +%F) release v1" | aws s3 cp - s3://$B/release/app.txt
printf '{"allowed": ["v1", "v2"]}' | aws s3 cp - s3://$B/config/allowed.json
aws s3 ls s3://$B --recursive

echo "== 1-5 드리프트 탐지(정상일 때 한 번)"
ID=$(aws cloudformation detect-stack-drift --stack-name $SID-iac-app --query StackDriftDetectionId --output text)
sleep 15
aws cloudformation describe-stack-drift-detection-status --stack-drift-detection-id $ID --query '[DetectionStatus,StackDriftStatus]' --output text

echo "== 1-6 SSM 문서: 앱 재시작 + 헬스 체크"
cat > ~/iac-restart-app.json <<'DOC'
{
  "schemaVersion": "2.2",
  "description": "opslab: restart the app service and check /health",
  "parameters": {
    "ServiceName": { "type": "String", "default": "app", "description": "systemd service" },
    "Port": { "type": "String", "default": "8080", "description": "health check port" }
  },
  "mainSteps": [ { "action": "aws:runShellScript", "name": "restartAndCheck", "inputs": { "runCommand": [
    "systemctl restart {{ServiceName}}",
    "for i in $(seq 1 15); do curl -sf http://127.0.0.1:{{Port}}/health && exit 0; sleep 2; done",
    "echo health check failed on port {{Port}}; exit 1" ] } } ]
}
DOC
aws ssm describe-document --name $SID-iac-restart-app >/dev/null 2>&1 || \
aws ssm create-document --name $SID-iac-restart-app --document-type Command --document-format JSON --content file://$HOME/iac-restart-app.json \
  --tags Key=Course,Value=opslab Key=Module,Value=iac Key=Owner,Value=$SID --query 'DocumentDescription.[Name,DocumentVersion,Status]' --output text
sleep 5
CID=$(aws ssm send-command --document-name $SID-iac-restart-app --targets Key=tag:Name,Values=$SID-cmp-app --max-concurrency 1 \
  --comment "rolling restart" --query Command.CommandId --output text)
aws ssm wait command-executed --command-id $CID --instance-id $(aws ssm list-command-invocations --command-id $CID --query 'CommandInvocations[0].InstanceId' --output text) 2>/dev/null || true
sleep 20
aws ssm list-command-invocations --command-id $CID --query 'CommandInvocations[].[InstanceId,Status]' --output table

echo "== 1-7 패치: 스캔(전체) → 설치(한 대씩, 재부팅 없이)"
CID=$(aws ssm send-command --document-name AWS-RunPatchBaseline --targets Key=tag:Name,Values=$SID-cmp-app \
  --parameters Operation=Scan --query Command.CommandId --output text)
sleep 90
aws ssm list-command-invocations --command-id $CID --query 'CommandInvocations[].[InstanceId,Status]' --output table
IDS=$(aws ec2 describe-instances --filters Name=tag:Name,Values=$SID-cmp-app Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId' --output text)
aws ssm describe-instance-patch-states --instance-ids $IDS --query 'InstancePatchStates[].[InstanceId,Operation,InstalledCount,MissingCount,FailedCount]' --output table
echo "✅ 1단계 명령 완료"
