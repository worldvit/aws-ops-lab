#!/bin/bash
# rel 모듈 공통 함수: 버킷·복제, Aurora(데이터 계층) 상태, AZ·서브넷, FIS, 비용 점검.
# 장애 스크립트는 common/lib.sh 의 SID·LAB 검사를 거친다. verify.sh·1단계 명령은 REL_NO_LAB=1 로 부른다.
D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
if [ -z "${REL_NO_LAB:-}" ]; then source "$D/../../common/lib.sh"; fi
DATA_NO_LAB=1 source "$D/../data/lib.sh"      # CLUSTER, WRITER_EP, WRITER_ID, READER_ID, LOADGEN, sql(), wait_cluster, alb_dns, app_ids
ACCT=$(aws sts get-caller-identity --query Account --output text)
DR_REGION=ap-northeast-1
SRC="$SID-rel-src-$ACCT"; DR="$SID-rel-dr-$ACCT"
REPL_ROLE_ARN="arn:aws:iam::$ACCT:role/$SID-rel-repl-role"
ASG="$SID-cmp-asg"
TPL_NAME="$SID-rel-az-drill"                  # 수강생이 만드는 AZ 장애 훈련 템플릿(Name 태그)
TAGS_KV="Key=Course,Value=opslab Key=Module,Value=rel Key=Owner,Value=$SID"

# ── 서브넷·AZ
app_subnets() { aws cloudformation list-exports --query "Exports[?Name=='$SID-base-AppSubnets'].Value" --output text | tr ',' ' '; }
SUB_A=$(app_subnets | awk '{print $1}'); SUB_C=$(app_subnets | awk '{print $2}')
az_of() { aws ec2 describe-subnets --subnet-ids "$1" --query 'Subnets[0].AvailabilityZone' --output text 2>/dev/null; }
asg_subnets() { aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" --query 'AutoScalingGroups[0].VPCZoneIdentifier' --output text | tr ',' ' '; }
asg_size() { aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" --query 'AutoScalingGroups[0].[MinSize,DesiredCapacity,MaxSize]' --output text | tr '\t' '/'; }
asg_ids() { aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" --query "AutoScalingGroups[0].Instances[?LifecycleState=='InService'].InstanceId" --output text; }
asg_azs() { aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" --query "AutoScalingGroups[0].Instances[?LifecycleState=='InService'].AvailabilityZone" --output text | tr '\t' '\n' | sort | uniq -c | xargs; }
writer_az() { aws rds describe-db-instances --db-instance-identifier "$(aws rds describe-db-clusters --db-cluster-identifier "$CLUSTER" --query 'DBClusters[0].DBClusterMembers[?IsClusterWriter].DBInstanceIdentifier|[0]' --output text)" --query 'DBInstances[0].AvailabilityZone' --output text 2>/dev/null; }
member_azs() { aws rds describe-db-instances --filters Name=db-cluster-id,Values="$CLUSTER" --query 'DBInstances[].[DBInstanceIdentifier,AvailabilityZone]' --output text | tr '\t\n' ': '; }

# ── 서비스 확인(ALB 경유)
code_of() { curl -s -o /dev/null -m 5 -w '%{http_code}' "http://$(alb_dns)$1"; }
ok_count() {  # $1=경로 $2=횟수 → 200 개수
  local n=0 i; for i in $(seq 1 "${2:-10}"); do [ "$(code_of "$1")" = 200 ] && n=$((n+1)); done; echo $n
}

# ── S3 교차 리전 복제
repl_json() {  # $1=복제 대상 접두사(비우면 전체)
  jq -nc --arg r "$REPL_ROLE_ARN" --arg d "arn:aws:s3:::$DR" --arg p "${1:-}" '{Role:$r,Rules:[{ID:"to-tokyo",Priority:1,Status:"Enabled",
    Filter:{Prefix:$p},DeleteMarkerReplication:{Status:"Enabled"},Destination:{Bucket:$d,StorageClass:"STANDARD"}}]}'
}
put_repl_policy() {  # 복제 역할 인라인 정책 replication (env.yaml 과 같은 내용)
  aws iam put-role-policy --role-name "$SID-rel-repl-role" --policy-name replication --policy-document "$(jq -nc --arg s "arn:aws:s3:::$SRC" --arg d "arn:aws:s3:::$DR" '{Version:"2012-10-17",Statement:[
    {Sid:"ReadSourceConfig",Effect:"Allow",Action:["s3:GetReplicationConfiguration","s3:ListBucket"],Resource:$s},
    {Sid:"ReadSourceObjects",Effect:"Allow",Action:["s3:GetObjectVersionForReplication","s3:GetObjectVersionAcl","s3:GetObjectVersionTagging"],Resource:($s+"/*")},
    {Sid:"WriteReplica",Effect:"Allow",Action:["s3:ReplicateObject","s3:ReplicateDelete","s3:ReplicateTags"],Resource:($d+"/*")}]}')"
}
crr_probe() {  # 원본에 data/probe-<시각>.txt 를 올리고 도쿄에 나타날 때까지(최대 $1초, 기본 180) → "걸린초 원본상태" 또는 "FAIL 원본상태"
  local k t0 i st; k="data/probe-$(date +%s).txt"; t0=$(date +%s)
  echo "opslab crr probe $(date -u +%FT%TZ)" | aws s3 cp - "s3://$SRC/$k" --only-show-errors || { echo "FAIL 업로드실패"; return; }
  for i in $(seq 1 $(( ${1:-180} / 5 ))); do
    aws s3api head-object --bucket "$DR" --key "$k" --region "$DR_REGION" >/dev/null 2>&1 && { echo "$(( $(date +%s) - t0 )) $(aws s3api head-object --bucket "$SRC" --key "$k" --query ReplicationStatus --output text)"; return; }
    st=$(aws s3api head-object --bucket "$SRC" --key "$k" --query ReplicationStatus --output text 2>/dev/null); [ "$st" = FAILED ] && break
    sleep 5
  done
  echo "FAIL ${st:-없음}"
}

# ── FIS
fis_running() {  # 내 학번 태그의 진행 중 실험 ID
  aws fis list-experiments --query "experiments[?(state.status=='running' || state.status=='initiating') && tags.Owner=='$SID'].id" --output text 2>/dev/null
}
wait_inservice() {  # ASG InService 가 $1대가 될 때까지(최대 $2초)
  local i; for i in $(seq 1 $(( ${2:-600} / 15 ))); do [ "$(wc -w <<<"$(asg_ids)")" -ge "$1" ] && return 0; sleep 15; done; return 1
}
