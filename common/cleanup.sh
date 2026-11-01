#!/bin/bash
# 비용 정리 스크립트 — 모듈별 독립 실습: 매일 끝에 L0 층을 뺀 그날의 리소스를 모두 지운다.
# 실행 위치: CloudShell
#   bash ~/opslab/common/cleanup.sh          # 매일 마지막: L0 층을 뺀 전부 삭제 (확인 질문 있음)
#   bash ~/opslab/common/cleanup.sh status   # 남아 있는 실습 리소스와 시간당 과금 리소스 보기
#   bash ~/opslab/common/cleanup.sh final    # 과정 마지막 날: 위 삭제 + 장애 주입 기록(SSM) 삭제
# L0 스택(<학번>-l0)과 그 리소스는 지우지 않는다(호스팅 영역 외 과금 없음).
set -uo pipefail
: "${SID:?SID 환경변수에 학번을 넣으세요. 예) source ~/opslab-env.sh}"
export AWS_REGION="${AWS_REGION:-ap-northeast-2}"
MODE="${1:-day}"
ROOT=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

status() {
  echo "== $SID 남은 실습 리소스 (L0 층 제외) =="
  echo "-- 스택 --"
  aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE ROLLBACK_COMPLETE DELETE_FAILED \
    --query "StackSummaries[?starts_with(StackName,'$SID-') && StackName!='$SID-l0'].[StackName,StackStatus]" --output text | sed 's/^/  /'
  echo "-- 시간당 과금 리소스 --"
  aws ec2 describe-nat-gateways --filter Name=tag:Owner,Values="$SID" Name=state,Values=available,pending \
    --query 'NatGateways[].[NatGatewayId,Tags[?Key==`Name`]|[0].Value]' --output text | sed 's/^/  NAT /'
  aws ec2 describe-instances --filters Name=tag:Owner,Values="$SID" Name=instance-state-name,Values=pending,running,stopping,stopped \
    --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`]|[0].Value,State.Name]' --output text | sed 's/^/  EC2 /'
  aws elbv2 describe-load-balancers --query "LoadBalancers[?starts_with(LoadBalancerName,'$SID-')].LoadBalancerName" --output text | tr '\t' '\n' | sed '/^$/d;s/^/  ALB /'
  aws elbv2 describe-target-groups --query "TargetGroups[?starts_with(TargetGroupName,'$SID-')].TargetGroupName" --output text | tr '\t' '\n' | sed '/^$/d;s/^/  TG  /'
  aws autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[?starts_with(AutoScalingGroupName,'$SID-')].AutoScalingGroupName" --output text | tr '\t' '\n' | sed '/^$/d;s/^/  ASG /'
  { aws ec2 describe-transit-gateways --filters Name=tag:Owner,Values="$SID" Name=state,Values=available,pending,deleting \
      --query 'TransitGateways[].[TransitGatewayId,State]' --output text
    aws ec2 describe-transit-gateways --filters Name=tag:Name,Values="$SID-*" Name=state,Values=available,pending,deleting \
      --query 'TransitGateways[].[TransitGatewayId,State]' --output text; } | sort -u | sed '/^$/d;s/^/  TGW /'
  aws network-firewall list-firewalls --query "Firewalls[?starts_with(FirewallName,'$SID-')].FirewallName" --output text 2>/dev/null | tr '\t' '\n' | sed '/^$/d;s/^/  FW  /'
  aws ec2 describe-vpc-endpoints --filters Name=tag:Owner,Values="$SID" Name=vpc-endpoint-type,Values=Interface \
    --query 'VpcEndpoints[].[VpcEndpointId,ServiceName]' --output text | sed 's/^/  VPCE /'
}

delete_all() {
  read -r -p "L0 층을 뺀 $SID 의 실습 리소스를 모두 삭제합니다. 학번($SID)을 입력하세요: " ans; [ "$ans" = "$SID" ] || exit 1
  # 1) 모듈별 정리 훅: 수강생이 CLI로 직접 만든 리소스 (modules/*/cleanup.sh)
  for h in "$ROOT"/modules/*/cleanup.sh; do bash "$h"; done
  # 1-1) 콘솔 "템플릿 파일 업로드"가 계정에 자동으로 만드는 버킷 cf-templates-<임의>-<리전>: 우리 템플릿 파일만 지우고, 비면 버킷도 지운다
  TPLS=$(find "$ROOT" -name '*.yaml' -exec grep -l AWSTemplateFormatVersion {} + 2>/dev/null | xargs -n1 basename | sort -u)
  for b in $(aws s3api list-buckets --query "Buckets[?starts_with(Name,'cf-templates-') && ends_with(Name,'-$AWS_REGION')].Name" --output text 2>/dev/null); do
    aws s3api list-object-versions --bucket "$b" --output json 2>/dev/null \
      | jq -r '(.Versions // []) + (.DeleteMarkers // []) | .[] | [.Key, .VersionId] | @tsv' \
      | while IFS=$'\t' read -r k v; do
          for t in $TPLS; do case "$k" in *"$t") aws s3api delete-object --bucket "$b" --key "$k" --version-id "$v" >/dev/null && echo "  콘솔 업로드 템플릿 삭제: $b/$k"; break;; esac; done
        done
    [ "$(aws s3api list-object-versions --bucket "$b" --query 'length([Versions,DeleteMarkers][])' --output text 2>/dev/null)" = 0 ] \
      && aws s3api delete-bucket --bucket "$b" 2>/dev/null && echo "  빈 버킷 삭제: $b"
  done
  # 2) 수강생이 만든 CloudWatch 알람 (<학번>-*)
  AL=$(aws cloudwatch describe-alarms --alarm-name-prefix "$SID-" --query 'MetricAlarms[].AlarmName' --output text)
  [ -n "$AL" ] && aws cloudwatch delete-alarms --alarm-names $AL && echo "  알람 삭제: $AL"
  # 3) 스택 (L0 제외, 늦게 만든 것부터)
  for st in $(aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE ROLLBACK_COMPLETE DELETE_FAILED \
               --query "reverse(sort_by(StackSummaries[?starts_with(StackName,'$SID-') && StackName!='$SID-l0'],&CreationTime))[].StackName" --output text); do
    echo "  스택 삭제: $st"; aws cloudformation delete-stack --stack-name "$st"; aws cloudformation wait stack-delete-complete --stack-name "$st" || echo "  ⚠️ $st 삭제 실패 — 콘솔에서 이벤트 확인"
  done
  # 4) 스택 삭제가 남긴 Aurora 최종 스냅샷(이전 템플릿의 기본 삭제 정책) — 저장 비용이 나가므로 삭제
  for s in $(aws rds describe-db-cluster-snapshots --snapshot-type manual --query "DBClusterSnapshots[?starts_with(DBClusterSnapshotIdentifier,'$SID-l3-snapshot-')].DBClusterSnapshotIdentifier" --output text); do
    aws rds delete-db-cluster-snapshot --db-cluster-snapshot-identifier "$s" >/dev/null && echo "  최종 스냅샷 삭제: $s"; done
}

case "$MODE" in
  status) status ;;
  day)    delete_all; status ;;
  final)
    delete_all
    N=$(aws ssm get-parameters-by-path --path /opslab/injections --recursive --query 'Parameters[].Name' --output text)
    [ -n "$N" ] && echo $N | xargs -n 10 aws ssm delete-parameters --names >/dev/null && echo "  장애 주입 기록 삭제"
    status ;;
  *) sed -n '2,7p' "$0"; exit 1 ;;
esac
