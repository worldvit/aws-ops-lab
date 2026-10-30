#!/bin/bash
# 공통: Run Command 도우미. 모듈 lib.sh 가 source 한다.
inst() { aws ec2 describe-instances --filters Name=tag:Name,Values="$1" Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null; }
ssm_run() {  # $1=인스턴스 ID(공백 구분 여러 개) $2=셸 명령 $3=최대 대기 초(기본 60) → 인스턴스별 표준 출력
  local ids=$1 cid n st i
  cid=$(aws ssm send-command --instance-ids $ids --document-name AWS-RunShellScript --comment "opslab" \
        --parameters "$(jq -nc --arg c "$2" --arg t "${3:-60}" '{commands:[$c],executionTimeout:[$t]}')" \
        --query Command.CommandId --output text) || return 1
  for n in $(seq 1 $(( ${3:-60} / 2 + 10 ))); do
    st=$(aws ssm list-commands --command-id "$cid" --query 'Commands[0].Status' --output text)
    case "$st" in Success|Failed|TimedOut|Cancelled) break;; esac; sleep 2
  done
  for i in $ids; do
    aws ssm get-command-invocation --command-id "$cid" --instance-id "$i" --query 'StandardOutputContent' --output text 2>/dev/null
  done
}
