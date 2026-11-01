#!/bin/bash
# rel 모듈 1단계 따라하기 명령 모음 — Notion 페이지의 명령과 같다. 따라잡기(start.sh rel full)도 이 스크립트를 쓴다.
#   source ~/opslab-env.sh && bash ~/opslab/common/start.sh rel && bash ~/opslab/tools/build/rel.sh
# SKIP_RESTORE=1 이면 1-3 의 복원 실측(약 20분)을 건너뛴다(스냅샷만 만든다).
set -euo pipefail
source ~/opslab-env.sh
REL_NO_LAB=1 source ~/opslab/modules/rel/lib.sh

echo "== 1-2 현재 백업 설정과 RPO 확인 → 보존 7일·삭제 방지"
aws rds describe-db-clusters --db-cluster-identifier $SID-data-db \
  --query 'DBClusters[0].[BackupRetentionPeriod,PreferredBackupWindow,EarliestRestorableTime,LatestRestorableTime,DeletionProtection]' --output text
aws rds modify-db-cluster --db-cluster-identifier $SID-data-db --backup-retention-period 7 --deletion-protection --apply-immediately \
  --query 'DBCluster.[BackupRetentionPeriod,DeletionProtection]' --output text
echo "   지금 시각 $(date -u +%FT%TZ) / 복원 가능한 가장 최근 시각 $(aws rds describe-db-clusters --db-cluster-identifier $SID-data-db --query 'DBClusters[0].LatestRestorableTime' --output text)"

echo "== 1-3 백업(스냅샷)과 복원 시간 실측"
T0=$(date +%s)
aws rds create-db-cluster-snapshot --db-cluster-identifier $SID-data-db --db-cluster-snapshot-identifier $SID-rel-snap-1 --tags $TAGS_KV \
  --query 'DBClusterSnapshot.[DBClusterSnapshotIdentifier,Status]' --output text
aws rds wait db-cluster-snapshot-available --db-cluster-snapshot-identifier $SID-rel-snap-1
T1=$(date +%s); echo "   스냅샷 완료: $((T1-T0))초"
if [ -z "${SKIP_RESTORE:-}" ]; then
  DBSG=$(aws cloudformation list-exports --query "Exports[?Name=='$SID-data-DbSg'].Value" --output text)
  VER=$(aws rds describe-db-clusters --db-cluster-identifier $SID-data-db --query 'DBClusters[0].EngineVersion' --output text)
  aws rds restore-db-cluster-from-snapshot --db-cluster-identifier $SID-rel-restore --snapshot-identifier $SID-rel-snap-1 \
    --engine aurora-postgresql --engine-version $VER --db-subnet-group-name $SID-data-subnets --vpc-security-group-ids $DBSG \
    --tags $TAGS_KV --query 'DBCluster.[DBClusterIdentifier,Status]' --output text
  aws rds create-db-instance --db-instance-identifier $SID-rel-restore-1 --db-cluster-identifier $SID-rel-restore \
    --engine aurora-postgresql --db-instance-class db.t4g.medium --tags $TAGS_KV --query 'DBInstance.[DBInstanceIdentifier,DBInstanceStatus]' --output text
  aws rds wait db-instance-available --db-instance-identifier $SID-rel-restore-1
  T2=$(date +%s); echo "   복원 클러스터 사용 가능: 스냅샷 뒤 $((T2-T1))초"
  EP=$(aws rds describe-db-clusters --db-cluster-identifier $SID-rel-restore --query 'DBClusters[0].Endpoint' --output text)
  echo "   복원본 데이터 확인: $(sql 'select count(*) from orders' opslab $EP | tr '\n' ' ')"
  T3=$(date +%s); echo "   실측 RTO(백업 시작 → 데이터 확인): $((T3-T0))초 = 약 $(( (T3-T0+59)/60 ))분"
  aws rds delete-db-instance --db-instance-identifier $SID-rel-restore-1 --query 'DBInstance.DBInstanceStatus' --output text
  aws rds delete-db-cluster --db-cluster-identifier $SID-rel-restore --skip-final-snapshot --query 'DBCluster.Status' --output text
fi

echo "== 1-4 S3 교차 리전 복제(서울 → 도쿄)"
aws s3api create-bucket --bucket $SRC --create-bucket-configuration LocationConstraint=ap-northeast-2 >/dev/null
aws s3api create-bucket --bucket $DR --region ap-northeast-1 --create-bucket-configuration LocationConstraint=ap-northeast-1 >/dev/null
for b in $SRC:ap-northeast-2 $DR:ap-northeast-1; do
  aws s3api put-bucket-versioning --bucket ${b%%:*} --region ${b##*:} --versioning-configuration Status=Enabled
  aws s3api put-bucket-tagging --bucket ${b%%:*} --region ${b##*:} --tagging "TagSet=[{Key=Course,Value=opslab},{Key=Module,Value=rel},{Key=Owner,Value=$SID}]"
done
repl_json > ~/rel-replication.json; cat ~/rel-replication.json
aws s3api put-bucket-replication --bucket $SRC --replication-configuration file://$HOME/rel-replication.json
echo "   복제 확인(걸린 초 / 원본 복제 상태): $(crr_probe 180)"

echo "== 1-5 AZ 장애 가정 훈련(FIS) — 안전장치 알람 + 실험 템플릿"
aws cloudwatch put-metric-alarm --alarm-name $SID-rel-drill-stop --alarm-description "opslab: AZ 훈련 중단 조건(ALB 5xx 폭증)" \
  --namespace AWS/ApplicationELB --metric-name HTTPCode_ELB_5XX_Count \
  --dimensions Name=LoadBalancer,Value=$(aws elbv2 describe-load-balancers --names $SID-cmp-alb --query 'LoadBalancers[0].LoadBalancerArn' --output text | sed 's#.*:loadbalancer/##') \
  --statistic Sum --period 60 --evaluation-periods 1 --threshold 300 --comparison-operator GreaterThanOrEqualToThreshold --treat-missing-data notBreaching --tags $TAGS_KV
jq -n --arg role "arn:aws:iam::$ACCT:role/opslab-fis" --arg sub "arn:aws:ec2:$AWS_REGION:$ACCT:subnet/$SUB_A" \
  --arg db "arn:aws:rds:$AWS_REGION:$ACCT:cluster:$SID-data-db" --arg al "arn:aws:cloudwatch:$AWS_REGION:$ACCT:alarm:$SID-rel-drill-stop" \
  --arg sid "$SID" --arg az "$(az_of $SUB_A)" '{
  description: ("opslab AZ 장애 가정 훈련: " + $az + " 앱·DB 서브넷 5분 단절 + Aurora 장애 조치"),
  roleArn: $role,
  stopConditions: [{source: "aws:cloudwatch:alarm", value: $al}],
  targets: {
    subnetA: {resourceType: "aws:ec2:subnet", resourceArns: [$sub], selectionMode: "ALL"},
    dbCluster: {resourceType: "aws:rds:cluster", resourceArns: [$db], selectionMode: "ALL"}},
  actions: {
    cutAzA: {actionId: "aws:network:disrupt-connectivity", parameters: {duration: "PT5M", scope: "all"}, targets: {Subnets: "subnetA"}},
    failoverDb: {actionId: "aws:rds:failover-db-cluster", targets: {Clusters: "dbCluster"}}},
  tags: {Name: ($sid + "-rel-az-drill"), Course: "opslab", Module: "rel", Owner: $sid}}' > ~/rel-az-drill.json
TID=$(aws fis create-experiment-template --cli-input-json file://$HOME/rel-az-drill.json --query experimentTemplate.id --output text); echo "   템플릿 $TID"
echo "   훈련 전: 앱 서버 AZ [$(asg_azs)], DB [$(member_azs)], 라이터 $(writer_az)"
if [ "$(writer_az)" != "$(az_of $SUB_A)" ]; then   # 라이터가 끊길 AZ 에 있어야 'DB 장애 조치'까지 훈련된다
  T=$(aws rds describe-db-instances --filters Name=db-cluster-id,Values=$SID-data-db --query "DBInstances[?AvailabilityZone=='$(az_of $SUB_A)'].DBInstanceIdentifier|[0]" --output text)
  aws rds failover-db-cluster --db-cluster-identifier $SID-data-db --target-db-instance-identifier $T >/dev/null; sleep 60; wait_cluster 600
  echo "   라이터를 $(writer_az) 로 옮겨 둠"
fi
EID=$(aws fis start-experiment --experiment-template-id $TID --tags Name=$SID-rel-az-drill,Course=opslab,Module=rel,Owner=$SID --query experiment.id --output text)
echo "   실험 $EID 시작 $(date +%T)"
for i in $(seq 1 24); do echo "   $(date +%T) /api $(code_of /api) /db $(code_of /db)  라이터 $(writer_az)"; sleep 15; done
aws fis get-experiment --id $EID --query 'experiment.[state.status,state.reason]' --output text
echo "   훈련 후: 앱 서버 AZ [$(asg_azs)], 라이터 $(writer_az)"

echo "== 1-6 비용 보는 곳 — 어제까지의 비용(서비스별)과 오늘의 리소스 목록"
aws ce get-cost-and-usage --time-period Start=$(date -u -d '-7 day' +%F),End=$(date -u +%F) --granularity DAILY --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE --query 'ResultsByTime[-1].Groups[?Metrics.UnblendedCost.Amount>`0.01`].[Keys[0],Metrics.UnblendedCost.Amount]' --output text 2>&1 | head -10 || true
aws resourcegroupstaggingapi get-resources --tag-filters Key=Owner,Values=$SID --query 'ResourceTagMappingList[].ResourceARN' --output text | tr '\t' '\n' | cut -d: -f3,6 | sort | uniq -c | sort -rn | head -15
