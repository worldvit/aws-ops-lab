#!/bin/bash
# cicd 모듈 공통 함수: 파이프라인 실행·승인·대기, 실패 액션 조회, 서비스 버전 확인.
# 장애 스크립트는 common/lib.sh 의 SID·LAB 검사를 거친다. verify.sh·구축 스크립트는 CICD_NO_LAB=1 로 부른다.
D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
if [ -n "${CICD_NO_LAB:-}" ]; then
  set -uo pipefail; : "${SID:?SID 환경변수에 학번을 넣으세요. 예) source ~/opslab-env.sh}"
  export AWS_REGION="${AWS_REGION:-ap-northeast-2}"
else
  source "$D/../../common/lib.sh"
fi
source "$D/../../common/ssm.sh"
PIPE="$SID-cicd-pipeline"; PROJ="$SID-cicd-build"
EC2APP="$SID-cicd-ec2"; EC2DG="$SID-cicd-ec2-dg"; ECSAPP="$SID-cicd-ecs"; ECSDG="$SID-cicd-ecs-dg"
RSTACK="$SID-cicd-release"; ENVSTACK="$SID-cicd-env"
ACCT=$(aws sts get-caller-identity --query Account --output text)
alb_dns() { aws elbv2 describe-load-balancers --names "$SID-cmp-alb" --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null; }
app_ids() { aws ec2 describe-instances --filters Name=tag:Name,Values="$SID-cmp-app" Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId' --output text; }
envout() { aws cloudformation describe-stacks --stack-name "$ENVSTACK" --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text 2>/dev/null; }
release() { aws ssm get-parameter --name /opslab/cicd/release --query Parameter.Value --output text 2>/dev/null || echo none; }
ver() {  # $1=포트(80|8000) → /api 의 version (5번 중 가장 많은 값)과 성공 수 "version ok/5"
  local i b v ok=0 vs=""; for i in 1 2 3 4 5; do
    b=$(curl -s -m 5 -w ' %{http_code}' "http://$(alb_dns):$1/api"); [ "${b##* }" = 200 ] && ok=$((ok+1))
    v=$(jq -r '.version // empty' <<<"${b% *}" 2>/dev/null); vs="$vs ${v:-?}"; done
  echo "$(tr ' ' '\n' <<<"$vs" | sed '/^$/d' | sort | uniq -c | sort -rn | awk 'NR==1{print $2}') $ok/5"
}
pipe_exists() { aws codepipeline get-pipeline --name "$PIPE" >/dev/null 2>&1; }
need_pipe() { pipe_exists || { echo "파이프라인 $PIPE 을 찾지 못했습니다. 1단계 구축을 먼저 끝내세요."; exit 3; }; }
start_release() {  # $1=AppVersion $2=ErrorRate → 실행 ID
  aws codepipeline start-pipeline-execution --name "$PIPE" \
    --variables name=AppVersion,value="$1" name=ErrorRate,value="${2:-0}" --query pipelineExecutionId --output text
}
exec_status() { aws codepipeline get-pipeline-execution --pipeline-name "$PIPE" --pipeline-execution-id "$1" --query pipelineExecution.status --output text 2>/dev/null; }
last_exec() { aws codepipeline list-pipeline-executions --pipeline-name "$PIPE" --max-items 1 --query 'pipelineExecutionSummaries[0].[pipelineExecutionId,status]' --output text 2>/dev/null | head -1; }
approve_if_waiting() {  # 승인 단계가 기다리고 있으면 승인($1 실행 ID 는 기록용 — 대기열에서 앞선 실행이 막고 있어도 풀어 준다)
  local tok; tok=$(aws codepipeline get-pipeline-state --name "$PIPE" --query "stageStates[?stageName=='Release'].actionStates[] | [?actionName=='Approve'].latestExecution | [?status=='InProgress'].token | [0]" --output text 2>/dev/null)
  [ -n "$tok" ] && [ "$tok" != None ] || return 1
  aws codepipeline put-approval-result --pipeline-name "$PIPE" --stage-name Release --action-name Approve --token "$tok" \
    --result summary="opslab auto approve",status=Approved >/dev/null && echo "  (승인 완료)" >&2
}
wait_exec() {  # $1=실행 ID $2=최대 초(기본 1500). AUTO_APPROVE=1 이면 승인 단계를 자동 승인. 결과 상태를 출력
  local i s; for i in $(seq 1 $(( ${2:-1500} / 10 ))); do
    s=$(exec_status "$1"); case "$s" in InProgress|Stopping|"") ;; *) echo "$s"; return 0;; esac
    [ -n "${AUTO_APPROVE:-}" ] && approve_if_waiting "$1"
    sleep 10; done; exec_status "$1"
}
failed_actions() {  # $1=실행 ID → 실패한 액션과 요약
  aws codepipeline list-action-executions --pipeline-name "$PIPE" --filter pipelineExecutionId="$1" \
    --query 'actionExecutionDetails[?status==`Failed`].[stageName,actionName,output.executionResult.externalExecutionSummary]' --output text 2>/dev/null
}
retry_failed() {  # $1=실행 ID — 실패한 단계를 다시 실행(같은 실행 ID 유지)
  local st; st=$(aws codepipeline list-action-executions --pipeline-name "$PIPE" --filter pipelineExecutionId="$1" --query 'actionExecutionDetails[?status==`Failed`].stageName | [0]' --output text)
  aws codepipeline retry-stage-execution --pipeline-name "$PIPE" --stage-name "$st" --pipeline-execution-id "$1" --retry-mode FAILED_ACTIONS >/dev/null
}
# 정상 릴리스로 되돌리기: 이전에 성공한 릴리스 번호(없으면 v1)로 새 실행 → 성공까지(자동 승인)
good_release() { local r; r=$(release); [ "$r" = none ] && r=v1; echo "$r"; }
redeploy_good() {  # $1=버전(기본: 현재 기록된 릴리스) → 결과 상태
  local v e; v=${1:-$(good_release)}; e=$(start_release "$v" 0) || return 1; AUTO_APPROVE=1 wait_exec "$e" 1800
}
# ── 장애 스크립트 도우미
DENY=opslab-fault-deny                      # 장애가 역할에 붙이는 인라인 거부 정책 이름
put_deny() {  # $1=역할 $2=액션(JSON 배열 문자열) $3=리소스(기본 *)
  aws iam put-role-policy --role-name "$1" --policy-name "$DENY" --policy-document \
    "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Deny\",\"Action\":$2,\"Resource\":\"${3:-*}\"}]}"
}
del_deny() { aws iam delete-role-policy --role-name "$1" --policy-name "$DENY" 2>/dev/null || true; }
new_ver() { echo "r$(date +%m%d%H%M%S)"; }   # 장애 실습용 새 릴리스 번호
traffic() {  # $1=초 — CloudShell 에서 :80·:8000 /api 로 초당 약 4건을 보낸다(알람이 반응할 만큼). 백그라운드
  local dns; dns=$(alb_dns)
  setsid nohup bash -c "end=\$((SECONDS+$1)); while [ \$SECONDS -lt \$end ]; do curl -s -o /dev/null -m 3 http://$dns/api; curl -s -o /dev/null -m 3 http://$dns:8000/api; sleep 0.25; done" >/dev/null 2>&1 < /dev/null &
}
retry_exec() {  # $1=실행 ID — 실패한 단계를 처음부터 다시(모든 액션) 실행하고 끝까지 기다린다(자동 승인). 3번까지
  local st r i; for i in 1 2 3; do
    st=$(aws codepipeline list-action-executions --pipeline-name "$PIPE" --filter pipelineExecutionId="$1" \
      --query 'actionExecutionDetails[?status==`Failed`].stageName | [0]' --output text)
    [ -n "$st" ] && [ "$st" != None ] || { exec_status "$1"; return 0; }
    aws codepipeline retry-stage-execution --pipeline-name "$PIPE" --stage-name "$st" --pipeline-execution-id "$1" --retry-mode ALL_ACTIONS >/dev/null 2>&1 || true
    sleep 15; r=$(AUTO_APPROVE=1 wait_exec "$1" 1800); [ "$r" = Succeeded ] && { echo "$r"; return 0; }
    sleep 30   # IAM 전파 등
  done; echo "$r"
}
