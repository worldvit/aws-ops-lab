#!/bin/bash
# auto 모듈 공통 함수: 이름 규칙, 앱 서버 찾기, Run Command·Automation 실행, 접속 기록 설정, Route 53 장애 조치.
# 장애 스크립트는 common/lib.sh 의 SID·LAB 검사를 거친다. verify.sh·1단계 명령은 AUTO_NO_LAB=1 로 부른다.
D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
if [ -n "${AUTO_NO_LAB:-}" ]; then
  set -uo pipefail; : "${SID:?SID 환경변수에 학번을 넣으세요. 예) source ~/opslab-env.sh}"
  export AWS_REGION="${AWS_REGION:-ap-northeast-2}"
else
  source "$D/../../common/lib.sh"
fi
source "$D/../../common/ssm.sh"
ACCT=$(aws sts get-caller-identity --query Account --output text)
ASG="$SID-cmp-asg"
APP_TAG="$SID-cmp-app"                       # 앱 서버 이름 태그(Run Command·런북의 대상)
LOGG="/opslab/$SID/sessions"                 # 접속 기록 로그 그룹
RCLOG="/opslab/$SID/runcommand"              # Run Command 출력 로그 그룹
PREF=SSM-SessionManagerRunShell              # 계정(리전)의 Session Manager 기본 설정 문서
RUNBOOK="$SID-auto-app-recover"              # 런북(Automation 문서)
SWITCH=/opslab/auto/enabled                  # 자동 조치 안전 스위치(on/off)
ALARM="$SID-auto-api-5xx"                    # 자동 복구를 부르는 알람
RULE="$SID-auto-recover"                     # 알람 → 런북 규칙
FRULE="$SID-auto-recover-failed"             # 런북 실패 → 알림 규칙
MW="$SID-auto-mw"                            # 유지관리 기간
HCNAME="$SID-auto-hc"                        # Route 53 헬스 체크 이름 태그
AUTO_ROLE_ARN="arn:aws:iam::$ACCT:role/$SID-auto-automation-role"
EVENTS_ROLE_ARN="arn:aws:iam::$ACCT:role/$SID-auto-events-role"
RUNBOOK_ARN="arn:aws:ssm:$AWS_REGION:$ACCT:automation-definition/$RUNBOOK:\$DEFAULT"

alb_dns() { aws elbv2 describe-load-balancers --names "$SID-cmp-alb" --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null; }
alb_full() { aws elbv2 describe-load-balancers --names "$SID-cmp-alb" --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null | sed 's#.*:loadbalancer/##'; }
listener_arn() { aws cloudformation list-exports --query "Exports[?Name=='$SID-cmp-ListenerArn'].Value" --output text; }
tg_arn() { aws elbv2 describe-target-groups --names "$SID-cmp-tg" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null; }
# ASG 의 InService 인스턴스(태그와 무관 — 태그가 지워져도 찾는다)
asg_ids() { aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" --query "AutoScalingGroups[0].Instances[?LifecycleState=='InService'].InstanceId" --output text 2>/dev/null; }
# 이름 태그로 찾은 실행 중 앱 서버
app_ids() { aws ec2 describe-instances --filters Name=tag:Name,Values="$APP_TAG" Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId' --output text; }
ping_of() { aws ssm describe-instance-information --filters Key=InstanceIds,Values="$1" --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null; }
env_out() { aws cloudformation describe-stacks --stack-name "$SID-auto-env" --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text 2>/dev/null; }
api_ok() {  # /api 를 $1번(기본 20) 호출해 200 개수
  local n=0 i; for i in $(seq 1 "${1:-20}"); do [ "$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://$(alb_dns)/api")" = 200 ] && n=$((n+1)); done; echo $n
}

# ── Session Manager 기본 설정(접속 기록) — 1단계·원복이 같은 내용을 쓴다
pref_json() {  # $1=로그 그룹 이름
  jq -nc --arg g "${1:-$LOGG}" '{schemaVersion:"1.0",description:"opslab session preferences",sessionType:"Standard_Stream",
    inputs:{s3BucketName:"",s3KeyPrefix:"",s3EncryptionEnabled:false,cloudWatchLogGroupName:$g,cloudWatchEncryptionEnabled:false,
      cloudWatchStreamingEnabled:true,kmsKeyId:"",runAsEnabled:false,runAsDefaultUser:"",idleSessionTimeout:"20",maxSessionDuration:"",
      shellProfile:{windows:"",linux:""}}}'
}
put_pref() {  # 설정 문서를 $1 로그 그룹으로(없으면 만들고, 있으면 새 버전을 기본으로)
  if aws ssm describe-document --name "$PREF" >/dev/null 2>&1; then
    local v; v=$(aws ssm update-document --name "$PREF" --content "$(pref_json "$1")" --document-version '$LATEST' --query DocumentDescription.DocumentVersion --output text 2>/dev/null) \
      || v=$(aws ssm describe-document --name "$PREF" --query Document.LatestVersion --output text)   # 내용이 같으면 DuplicateDocumentContent — 최신 버전이 이미 그 내용
    aws ssm update-document-default-version --name "$PREF" --document-version "$v" >/dev/null 2>&1
    return 0
  fi
  aws ssm create-document --name "$PREF" --document-type Session --content "$(pref_json "$1")" >/dev/null
}
pref_group() { aws ssm get-document --name "$PREF" --query Content --output text 2>/dev/null | jq -r '.inputs.cloudWatchLogGroupName // ""'; }
# 비대화형 세션으로 명령 하나 실행 → 출력(세션 연결 시험). $1=인스턴스 $2=표시 문자열
session_probe() {
  timeout 60 aws ssm start-session --target "$1" --document-name AWS-StartInteractiveCommand \
    --parameters "{\"command\":[\"echo $2\"]}" 2>&1 | tr -d '\r'
}

# ── Run Command: 태그 대상 + 동시 실행 제한 → "명령ID 대상수 성공수"
run_tag() {  # $1=셸 명령 $2=동시 실행(기본 50%) $3=허용 오류(기본 0)
  local cid st n
  cid=$(aws ssm send-command --document-name AWS-RunShellScript --targets "Key=tag:Name,Values=$APP_TAG" \
        --max-concurrency "${2:-50%}" --max-errors "${3:-0}" --timeout-seconds 60 --comment "opslab auto" \
        --parameters "$(jq -nc --arg c "$1" '{commands:[$c],executionTimeout:["60"]}')" \
        --query Command.CommandId --output text 2>/dev/null) || { echo "- 0 0"; return; }
  for n in $(seq 1 60); do
    st=$(aws ssm list-commands --command-id "$cid" --query 'Commands[0].Status' --output text)
    case "$st" in Success|Failed|TimedOut|Cancelled) break;; esac; sleep 3
  done
  aws ssm list-commands --command-id "$cid" --query 'Commands[0].[CommandId,TargetCount,CompletedCount]' --output text | {
    read -r c t _; echo "$c $t $(aws ssm list-command-invocations --command-id "$c" --query "length(CommandInvocations[?Status=='Success'])" --output text)"; }
}
set_error_rate() {  # 앱 서버 모두(ASG 기준)의 /api 오류율을 $1 로 — 장애 주입·원복용
  ssm_run "$(asg_ids)" "sed -i 's/^APP_ERROR_RATE=.*/APP_ERROR_RATE=$1/' /etc/app/app.env && systemctl restart app && sleep 3 && curl -sf -o /dev/null http://127.0.0.1:8080/health && echo ok" 60 >/dev/null
}

# ── Automation 실행 → 최종 상태 (최대 $2초, 기본 300)
run_runbook() {  # $1=추가 매개변수 JSON(선택)
  local p='{}'; [ -n "${1:-}" ] && p=$1
  aws ssm start-automation-execution --document-name "$RUNBOOK" --parameters "$p" --query AutomationExecutionId --output text 2>&1
}
wait_runbook() {  # $1=실행 ID
  local i s; for i in $(seq 1 $(( ${2:-300} / 5 ))); do
    s=$(aws ssm get-automation-execution --automation-execution-id "$1" --query AutomationExecution.AutomationExecutionStatus --output text 2>/dev/null)
    case "$s" in Success|Failed|TimedOut|Cancelled|CompletedWithFailure) echo "$s"; return;; esac; sleep 5
  done; echo "${s:-Unknown}"
}
runbook_since() {  # $1=기준 시각(epoch) 이후 시작된 런북 실행 ID(최대 $2초 기다림, 기본 120) — 알람·규칙이 시작했는지 확인용
  local t e i; t=$(date -u -d @"$1" +%Y-%m-%dT%H:%M:%SZ)
  for i in $(seq 1 $(( ${2:-120} / 5 ))); do
    e=$(aws ssm describe-automation-executions --filters Key=DocumentNamePrefix,Values="$RUNBOOK" Key=StartTimeAfter,Values="$t" \
        --query 'AutomationExecutionMetadataList[0].AutomationExecutionId' --output text 2>/dev/null)
    [ -n "$e" ] && [ "$e" != None ] && { echo "$e"; return; }; sleep 5
  done; echo None
}
failed_step() {  # 실패한 단계와 이유
  aws ssm get-automation-execution --automation-execution-id "$1" \
    --query "AutomationExecution.StepExecutions[?StepStatus!='Success'].[StepName,StepStatus,FailureMessage]" --output text 2>/dev/null | head -3
}

# ── Route 53: 하위 도메인 영역·레코드·헬스 체크
domain() { aws cloudformation describe-stacks --stack-name "$SID-l0" --query "Stacks[0].Parameters[?ParameterKey=='InstructorDomain'].ParameterValue" --output text 2>/dev/null; }
ZONE_NAME="$SID.$(domain)"; REC="app.$ZONE_NAME"
zone_id() { aws route53 list-hosted-zones-by-name --dns-name "$ZONE_NAME" --max-items 1 --query "HostedZones[?Name=='$ZONE_NAME.'].Id | [0]" --output text | sed 's#/hostedzone/##'; }
hc_id() { aws route53 list-health-checks --query "HealthChecks[?HealthCheckConfig.FullyQualifiedDomainName=='$(alb_dns)'].Id | [0]" --output text 2>/dev/null; }
alb_zone() { aws elbv2 describe-load-balancers --names "$SID-cmp-alb" --query 'LoadBalancers[0].CanonicalHostedZoneId' --output text; }
primary_rr() {  # $1=헬스 체크 ID(비우면 연결 안 함) → UPSERT 변경 JSON
  jq -nc --arg n "$REC" --arg z "$(alb_zone)" --arg d "dualstack.$(alb_dns)" --arg h "${1:-}" \
    '{Changes:[{Action:"UPSERT",ResourceRecordSet:({Name:$n,Type:"A",SetIdentifier:"primary",Failover:"PRIMARY",
      AliasTarget:{HostedZoneId:$z,DNSName:$d,EvaluateTargetHealth:false}} + (if $h=="" then {} else {HealthCheckId:$h} end))}]}'
}
secondary_rr() {
  jq -nc --arg n "$REC" --arg ip "$(env_out StandbyIp)" \
    '{Changes:[{Action:"UPSERT",ResourceRecordSet:{Name:$n,Type:"A",SetIdentifier:"secondary",Failover:"SECONDARY",TTL:30,ResourceRecords:[{Value:$ip}]}}]}'
}
dns_answer() { aws route53 test-dns-answer --hosted-zone-id "$(zone_id)" --record-name "$REC" --record-type A --query 'RecordData' --output text 2>/dev/null; }
hc_healthy() {  # 헬스 체커 중 Success 비율 "성공수/전체수"
  aws route53 get-health-check-status --health-check-id "$1" --query 'HealthCheckObservations[].StatusReport.Status' --output json 2>/dev/null \
    | jq -r '"\([.[]|select(startswith("Success"))]|length)/\(length)"'
}

# ── 정상 상태 원본(1단계·원복이 같은 내용을 쓴다)
put_auto_policy() {  # 자동화 역할의 인라인 정책 automation (env.yaml 과 같은 내용)
  aws iam put-role-policy --role-name "$SID-auto-automation-role" --policy-name automation --policy-document "$(jq -nc --arg p "arn:aws:ssm:$AWS_REGION:$ACCT:parameter/opslab/auto/*" '{Version:"2012-10-17",Statement:[
    {Sid:"RunCommand",Effect:"Allow",Action:["ssm:SendCommand","ssm:ListCommands","ssm:ListCommandInvocations","ssm:GetCommandInvocation","ssm:CancelCommand","ssm:DescribeInstanceInformation"],Resource:"*"},
    {Sid:"FindTargets",Effect:"Allow",Action:["ec2:DescribeInstances"],Resource:"*"},
    {Sid:"SafetySwitch",Effect:"Allow",Action:["ssm:GetParameter"],Resource:$p}]}')"
}
put_events_policy() {  # EventBridge 역할의 인라인 정책 start-automation (env.yaml 과 같은 내용)
  aws iam put-role-policy --role-name "$SID-auto-events-role" --policy-name start-automation --policy-document "$(jq -nc \
    --arg a "arn:aws:ssm:$AWS_REGION:$ACCT:automation-definition/$SID-auto-*" --arg r "$AUTO_ROLE_ARN" '{Version:"2012-10-17",Statement:[
    {Effect:"Allow",Action:"ssm:StartAutomationExecution",Resource:$a},{Effect:"Allow",Action:"iam:PassRole",Resource:$r}]}')"
}
put_alarm() {  # 1-5 의 알람
  aws cloudwatch put-metric-alarm --alarm-name "$ALARM" --alarm-description "opslab: 앱 5xx 증가 → 자동 복구 런북" \
    --namespace AWS/ApplicationELB --metric-name HTTPCode_Target_5XX_Count --dimensions Name=LoadBalancer,Value="$(alb_full)" \
    --statistic Sum --period 60 --evaluation-periods 1 --threshold "${1:-10}" --comparison-operator GreaterThanOrEqualToThreshold \
    --treat-missing-data notBreaching --tags Key=Course,Value=opslab Key=Module,Value=auto Key=Owner,Value="$SID"
}
runbook_content() { sed -e "s|__SID__|$SID|g" -e "s|__ROLE__|$AUTO_ROLE_ARN|g" "$D/runbook.yaml"; }
