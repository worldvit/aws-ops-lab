#!/bin/bash
# iac 모듈 공통 함수: 수강생 스택(<학번>-iac-app) 상태·매개변수, 템플릿 배포, SSM 문서 원본, 앱 서버 Run Command.
# 장애 스크립트는 common/lib.sh 의 SID·LAB 검사를 거친다. verify.sh 는 IAC_NO_LAB=1 로 부른다.
D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
if [ -n "${IAC_NO_LAB:-}" ]; then
  set -uo pipefail; : "${SID:?SID 환경변수에 학번을 넣으세요. 예) source ~/opslab-env.sh}"
  export AWS_REGION="${AWS_REGION:-ap-northeast-2}"
else
  source "$D/../../common/lib.sh"
fi
source "$D/../../common/ssm.sh"
STACK="$SID-iac-app"
TPL="$D/iac-app.yaml"
DOC="$SID-iac-restart-app"
ACCT=$(aws sts get-caller-identity --query Account --output text)
alb_dns() { aws elbv2 describe-load-balancers --names "$SID-cmp-alb" --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null; }
app_ids() { aws ec2 describe-instances --filters Name=tag:Name,Values="$SID-cmp-app" Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId' --output text; }
listener_arn() { aws cloudformation list-exports --query "Exports[?Name=='$SID-cmp-ListenerArn'].Value" --output text; }
stack_status() { aws cloudformation describe-stacks --stack-name "$STACK" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo NONE; }
sparam() { aws cloudformation describe-stacks --stack-name "$STACK" --query "Stacks[0].Parameters[?ParameterKey=='$1'].ParameterValue" --output text 2>/dev/null; }
soutput() { aws cloudformation describe-stacks --stack-name "$STACK" --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text 2>/dev/null; }
sres() { aws cloudformation describe-stack-resource --stack-name "$STACK" --logical-resource-id "$1" --query StackResourceDetail.PhysicalResourceId --output text 2>/dev/null; }
deploy_app() {  # $@=Key=Value 매개변수 덮어쓰기(나머지는 이전 값 유지). 결과: 0 성공 / 1 실패
  aws cloudformation deploy --stack-name "$STACK" --template-file "$TPL" --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides StudentId="$SID" "$@" --tags Course=opslab Module=iac Owner="$SID" --no-fail-on-empty-changeset >/dev/null 2>&1
}
wait_stack() {  # 진행 중(_IN_PROGRESS)이 끝날 때까지(최대 $1초, 기본 900)
  local i s; for i in $(seq 1 $(( ${1:-900} / 10 ))); do s=$(stack_status); [[ "$s" == *_IN_PROGRESS ]] || { echo "$s"; return 0; }; sleep 10; done; stack_status
}
# SSM 문서 원본(정상 상태) — 1단계 구축·원복이 같은 내용을 쓴다
doc_json() {  # $1=ServiceName 기본값 $2=Port 기본값
  jq -nc --arg s "${1:-app}" --arg p "${2:-8080}" '{schemaVersion:"2.2",description:"opslab: restart the app service and check /health",
    parameters:{ServiceName:{type:"String",default:$s,description:"systemd service"},Port:{type:"String",default:$p,description:"health check port"}},
    mainSteps:[{action:"aws:runShellScript",name:"restartAndCheck",inputs:{runCommand:[
      "systemctl restart {{ServiceName}}",
      "for i in $(seq 1 15); do curl -sf http://127.0.0.1:{{Port}}/health && exit 0; sleep 2; done",
      "echo health check failed on port {{Port}}; exit 1"]}}]}'
}
run_doc() {  # 기본 버전으로 모든 앱 서버에서 실행 → "성공수 전체수"
  local ids cid n t; ids=$(app_ids); t=$(wc -w <<<"$ids")
  cid=$(aws ssm send-command --document-name "$DOC" --instance-ids $ids --comment "opslab verify" --query Command.CommandId --output text 2>/dev/null) || { echo "0 $t"; return; }
  for n in $(seq 1 40); do
    s=$(aws ssm list-commands --command-id "$cid" --query 'Commands[0].Status' --output text)
    case "$s" in Success|Failed|TimedOut|Cancelled) break;; esac; sleep 3
  done
  echo "$(aws ssm list-command-invocations --command-id "$cid" --query "length(CommandInvocations[?Status=='Success'])" --output text) $t"
}
need_stack() { [ "$(stack_status)" != NONE ] || { echo "스택 $STACK 을 찾지 못했습니다. 1단계 구축을 먼저 끝내세요."; exit 3; }; }
