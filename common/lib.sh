#!/bin/bash
# 장애 스크립트(dayN/<장애명>/{inject,rollback}.sh) 공통 함수.
# 직접 실행하지 않는다. common/inject.sh 가 SID·LAB 을 정해 호출한다.
# 모든 변경은 이름이 $SID-d1-* 이고 태그 Course=opslab 이 붙은 리소스에만 한다.
set -uo pipefail
: "${SID:?SID 환경변수가 필요합니다}"; : "${LAB:?LAB 환경변수가 필요합니다}"
export AWS_REGION="${AWS_REGION:-ap-northeast-2}"
STATE="/opslab/injections/$LAB"        # 이 Lab의 주입 기록(SSM Parameter Store) 경로

ASG="$SID-d1-asg"
TG_ARN=$(aws elbv2 describe-target-groups --names "$SID-d1-tg" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null)
ALB_ARN=$(aws elbv2 describe-load-balancers --names "$SID-d1-alb" --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null)
ALB_SG=$(aws ec2 describe-security-groups --filters Name=group-name,Values="$SID-d1-alb-sg" Name=tag:Course,Values=opslab --query 'SecurityGroups[0].GroupId' --output text)
APP_SG=$(aws ec2 describe-security-groups --filters Name=group-name,Values="$SID-d1-app-sg" Name=tag:Course,Values=opslab --query 'SecurityGroups[0].GroupId' --output text)
LT_ID=$(aws ec2 describe-launch-templates --launch-template-names "$SID-d1-lt" --query 'LaunchTemplates[0].LaunchTemplateId' --output text 2>/dev/null)
for v in TG_ARN ALB_ARN ALB_SG APP_SG LT_ID; do
  case "${!v}" in ""|None) echo "Day 1 구축 리소스($v)를 찾지 못했습니다. 1~2단계를 먼저 끝내세요."; exit 3;; esac
done

pick_variant() { echo "${VARIANT:-$(( (RANDOM % $1) + 1 ))}"; }          # 1..$1 중 무작위
save()   { aws ssm put-parameter --name "$STATE/$1" --type String --value "$2" --overwrite >/dev/null; }  # 원복용 이전 값
load()   { aws ssm get-parameter --name "$STATE/$1" --query Parameter.Value --output text 2>/dev/null; }
record() { save variant "$1"; }                                          # 변형 번호

asg_lt_version() {  # ASG가 쓰는 시작 템플릿 버전을 숫자로 돌려준다
  local v; v=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" --query 'AutoScalingGroups[0].LaunchTemplate.Version' --output text)
  case "$v" in
    '$Latest')  aws ec2 describe-launch-templates --launch-template-ids "$LT_ID" --query 'LaunchTemplates[0].LatestVersionNumber' --output text;;
    '$Default') aws ec2 describe-launch-templates --launch-template-ids "$LT_ID" --query 'LaunchTemplates[0].DefaultVersionNumber' --output text;;
    *) echo "$v";;
  esac
}
app_ids() { aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId' --output text; }
run_on_app() {  # $1 = 모든 앱 서버에서 실행할 셸 명령 (Run Command)
  local ids cid; ids=$(app_ids); [ -z "$ids" ] && { echo "실행 중인 앱 서버가 없습니다"; return 1; }
  cid=$(aws ssm send-command --instance-ids $ids --document-name AWS-RunShellScript \
        --parameters "$(jq -nc --arg c "$1" '{commands:[$c]}')" --comment "opslab maintenance" --query Command.CommandId --output text)
  aws ssm wait command-executed --command-id "$cid" --instance-id "${ids%%[[:space:]]*}" 2>/dev/null
  echo "  Run Command $cid"
}
new_lt_version() {  # $1 = 사용자 데이터(평문) $2 = 버전 설명 → 새 버전 번호
  local ud; ud=$(printf '%s' "$1" | base64 -w0)
  aws ec2 create-launch-template-version --launch-template-id "$LT_ID" --source-version "$(asg_lt_version)" \
    --version-description "$2" --launch-template-data "{\"UserData\":\"$ud\"}" \
    --query LaunchTemplateVersion.VersionNumber --output text
}
