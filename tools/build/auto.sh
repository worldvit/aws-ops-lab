#!/bin/bash
# auto 모듈 1단계 따라하기 명령 모음 — Notion 페이지의 명령과 같다. 따라잡기(start.sh auto full)도 이 스크립트를 쓴다.
#   source ~/opslab-env.sh && bash ~/opslab/common/start.sh auto && bash ~/opslab/tools/build/auto.sh
# OPS_EMAIL=<메일 주소> 를 주면 1-6 에서 운영 알림 메일 구독을 만든다(메일의 Confirm 링크는 사람이 눌러야 함).
set -euo pipefail
source ~/opslab-env.sh
AUTO_NO_LAB=1 source ~/opslab/modules/auto/lib.sh
TAGS="Key=Course,Value=opslab Key=Module,Value=auto Key=Owner,Value=$SID"
echo "   앱 서버: $(app_ids)"

echo "== 1-2 Session Manager 접속 기록 (CloudWatch Logs)"
aws logs create-log-group --log-group-name /opslab/$SID/sessions --tags Course=opslab,Module=auto,Owner=$SID 2>/dev/null || true
aws logs put-retention-policy --log-group-name /opslab/$SID/sessions --retention-in-days 7
cat > ~/auto-session-pref.json <<EOF
{
  "schemaVersion": "1.0",
  "description": "opslab session preferences",
  "sessionType": "Standard_Stream",
  "inputs": {
    "s3BucketName": "", "s3KeyPrefix": "", "s3EncryptionEnabled": false,
    "cloudWatchLogGroupName": "/opslab/$SID/sessions",
    "cloudWatchEncryptionEnabled": false,
    "cloudWatchStreamingEnabled": true,
    "kmsKeyId": "", "runAsEnabled": false, "runAsDefaultUser": "",
    "idleSessionTimeout": "20", "maxSessionDuration": "",
    "shellProfile": { "windows": "", "linux": "" }
  }
}
EOF
if aws ssm describe-document --name SSM-SessionManagerRunShell >/dev/null 2>&1; then
  V=$(aws ssm update-document --name SSM-SessionManagerRunShell --content file://$HOME/auto-session-pref.json --document-version '$LATEST' \
      --query DocumentDescription.DocumentVersion --output text 2>/dev/null) && aws ssm update-document-default-version --name SSM-SessionManagerRunShell --document-version $V >/dev/null || true
else
  aws ssm create-document --name SSM-SessionManagerRunShell --document-type Session --content file://$HOME/auto-session-pref.json --query DocumentDescription.Status --output text
fi
APP1=$(app_ids | awk '{print $1}')
echo "   접속 시험: $(session_probe $APP1 opslab-session-check | grep -c opslab-session-check) 줄"
sleep 20
aws logs filter-log-events --log-group-name /opslab/$SID/sessions --filter-pattern opslab-session-check --query 'events[].[logStreamName]' --output text | head -3

echo "== 1-3 Run Command — 이름 태그로 모든 앱 서버에 동시에(절반씩, 오류 0개 허용)"
aws logs create-log-group --log-group-name /opslab/$SID/runcommand --tags Course=opslab,Module=auto,Owner=$SID 2>/dev/null || true
aws logs put-retention-policy --log-group-name /opslab/$SID/runcommand --retention-in-days 7
CID=$(aws ssm send-command --document-name AWS-RunShellScript --comment "opslab 1-3 점검" \
  --targets Key=tag:Name,Values=$SID-cmp-app --max-concurrency 50% --max-errors 0 \
  --parameters 'commands=["hostname","systemctl is-active app","grep APP_ERROR_RATE /etc/app/app.env","df -h / | tail -1"]' \
  --cloud-watch-output-config CloudWatchOutputEnabled=true,CloudWatchLogGroupName=/opslab/$SID/runcommand \
  --query Command.CommandId --output text)
echo "   명령 ID $CID"; sleep 15
aws ssm list-command-invocations --command-id $CID --details --query 'CommandInvocations[].[InstanceId,Status,CommandPlugins[0].Output]' --output text

echo "== 1-4 런북(SSM Automation) — 안전 스위치 + 문서 만들기 + 수동 실행"
aws ssm put-parameter --name /opslab/auto/enabled --type String --value on --overwrite --description "opslab 자동 조치 안전 스위치(on/off)" >/dev/null
sed -e "s|__SID__|$SID|g" -e "s|__ROLE__|$AUTOMATION_ROLE_ARN|g" ~/opslab/modules/auto/runbook.yaml > ~/auto-runbook.yaml
aws ssm create-document --name $SID-auto-app-recover --document-type Automation --document-format YAML \
  --content file://$HOME/auto-runbook.yaml --tags $TAGS --query DocumentDescription.[Name,Status] --output text
sleep 5
EID=$(aws ssm start-automation-execution --document-name $SID-auto-app-recover --query AutomationExecutionId --output text)
echo "   실행 $EID → $(wait_runbook $EID)"
aws ssm get-automation-execution --automation-execution-id $EID --query 'AutomationExecution.StepExecutions[].[StepName,StepStatus]' --output text

echo "== 1-5 알람 → EventBridge → 런북 (자동 복구 연결)"
LB=$(alb_full)
aws cloudwatch put-metric-alarm --alarm-name $SID-auto-api-5xx --alarm-description "opslab: 앱 5xx 증가 → 자동 복구 런북" \
  --namespace AWS/ApplicationELB --metric-name HTTPCode_Target_5XX_Count --dimensions Name=LoadBalancer,Value=$LB \
  --statistic Sum --period 60 --evaluation-periods 1 --threshold 10 --comparison-operator GreaterThanOrEqualToThreshold \
  --treat-missing-data notBreaching --tags $TAGS
cat > ~/auto-rule.json <<EOF
{
  "source": ["aws.cloudwatch"],
  "detail-type": ["CloudWatch Alarm State Change"],
  "detail": { "alarmName": ["$SID-auto-api-5xx"], "state": { "value": ["ALARM"] } }
}
EOF
aws events put-rule --name $SID-auto-recover --event-pattern file://$HOME/auto-rule.json --state ENABLED \
  --description "opslab: 5xx 알람 → 앱 복구 런북" --tags $TAGS --query RuleArn --output text
aws events put-targets --rule $SID-auto-recover --targets "[{\"Id\":\"runbook\",\"Arn\":\"arn:aws:ssm:$AWS_REGION:$ACCT:automation-definition/$SID-auto-app-recover:\$DEFAULT\",\"RoleArn\":\"$EVENTS_ROLE_ARN\",\"Input\":\"{\\\"AutomationAssumeRole\\\":[\\\"$AUTOMATION_ROLE_ARN\\\"]}\"}]" \
  --query FailedEntryCount --output text
echo "   연결 시험: 알람 상태를 잠시 ALARM 으로 바꿔 런북이 시작되는지 본다"
T0=$(date +%s)
aws cloudwatch set-alarm-state --alarm-name $SID-auto-api-5xx --state-value ALARM --state-reason "opslab 1-5 연결 시험"
E=$(runbook_since $T0 120)
echo "   알람이 시작한 실행: $E → $(wait_runbook $E)"

echo "== 1-6 안전장치 — 런북이 실패하면 운영 알림(SNS)"
cat > ~/auto-failed-rule.json <<EOF
{
  "source": ["aws.ssm"],
  "detail-type": ["EC2 Automation Execution Status-change Notification"],
  "detail": { "Definition": ["$SID-auto-app-recover"], "Status": ["Failed", "TimedOut", "Cancelled"] }
}
EOF
aws events put-rule --name $SID-auto-recover-failed --event-pattern file://$HOME/auto-failed-rule.json --state ENABLED \
  --description "opslab: 자동 복구 런북 실패 → 운영 알림" --tags $TAGS --query RuleArn --output text
aws events put-targets --rule $SID-auto-recover-failed --targets "Id=ops,Arn=$OPS_TOPIC_ARN" --query FailedEntryCount --output text
[ -n "${OPS_EMAIL:-}" ] && aws sns subscribe --topic-arn $OPS_TOPIC_ARN --protocol email --notification-endpoint "$OPS_EMAIL" --query SubscriptionArn --output text
echo "   안전 스위치 시험: off → 런북 실행 → 첫 단계에서 멈추는지"
aws ssm put-parameter --name /opslab/auto/enabled --value off --overwrite >/dev/null
EID=$(aws ssm start-automation-execution --document-name $SID-auto-app-recover --query AutomationExecutionId --output text)
echo "   스위치 off 실행 $EID → $(wait_runbook $EID)   $(failed_step $EID | cut -c1-120)"
aws ssm put-parameter --name /opslab/auto/enabled --value on --overwrite >/dev/null

echo "== 1-7 Patch Manager 유지관리 기간 (실습용 15분 주기, 스캔만)"
MWID=$(aws ssm create-maintenance-window --name $SID-auto-mw --schedule "cron(0/15 * * * ? *)" --schedule-timezone Asia/Seoul \
  --duration 1 --cutoff 0 --no-allow-unassociated-targets --tags $TAGS --query WindowId --output text)
WTID=$(aws ssm register-target-with-maintenance-window --window-id $MWID --resource-type INSTANCE --name app-servers \
  --targets Key=tag:Name,Values=$SID-cmp-app --query WindowTargetId --output text)
aws ssm register-task-with-maintenance-window --window-id $MWID --name patch-scan --task-type RUN_COMMAND --task-arn AWS-RunPatchBaseline \
  --targets Key=WindowTargetIds,Values=$WTID --max-concurrency 1 --max-errors 0 --priority 1 \
  --task-invocation-parameters '{"RunCommand":{"Parameters":{"Operation":["Scan"]},"TimeoutSeconds":600}}' --query WindowTaskId --output text
aws ssm get-maintenance-window --window-id $MWID --query '[Name,Enabled,Schedule,NextExecutionTime]' --output text

echo "== 1-8 Route 53 헬스 체크 기반 자동 전환 (app.$SID.<도메인>)"
ZID=$(zone_id); echo "   영역 $ZONE_NAME ($ZID), 레코드 $REC"
HC=$(aws route53 create-health-check --caller-reference $SID-auto-$(date +%s) \
  --health-check-config "Type=HTTP,FullyQualifiedDomainName=$ALB_DNS,Port=80,ResourcePath=/health,RequestInterval=10,FailureThreshold=2" \
  --query HealthCheck.Id --output text)
aws route53 change-tags-for-resource --resource-type healthcheck --resource-id $HC \
  --add-tags Key=Name,Value=$SID-auto-hc Key=Course,Value=opslab Key=Module,Value=auto Key=Owner,Value=$SID
primary_rr $HC > ~/auto-primary.json; secondary_rr > ~/auto-secondary.json
aws route53 change-resource-record-sets --hosted-zone-id $ZID --change-batch file://$HOME/auto-primary.json --query ChangeInfo.Status --output text
aws route53 change-resource-record-sets --hosted-zone-id $ZID --change-batch file://$HOME/auto-secondary.json --query ChangeInfo.Status --output text
echo "   헬스 체크 판정 대기 60초"; sleep 60
echo "   헬스 체커 $(hc_healthy $HC) 정상,  DNS 응답: $(dns_answer | tr '\t' ' ')   (예비 서버 IP $STANDBY_IP)"
