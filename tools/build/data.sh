#!/bin/bash
# data 모듈 1단계 따라하기 명령 모음 — Notion 페이지의 명령과 같다. 작성자가 따라하기 명령을 한 번에 검증할 때 쓴다.
#   source ~/opslab-env.sh && bash ~/opslab/common/start.sh data && source ~/opslab-env.sh && bash ~/opslab/tools/build/data.sh
set -euo pipefail
source ~/opslab-env.sh
T="Key=Course,Value=opslab Key=Module,Value=data Key=Owner,Value=$SID"

echo "== 1-2 보안 그룹과 DB 서브넷 그룹"
DB_SG=$(aws ec2 create-security-group --group-name $SID-data-db-sg --description "Aurora - 5432 from base VPC" --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$SID-data-db-sg},{Key=Course,Value=opslab},{Key=Module,Value=data},{Key=Owner,Value=$SID}]" \
  --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id $DB_SG --protocol tcp --port 5432 --cidr 10.0.0.0/16 >/dev/null
aws rds create-db-subnet-group --db-subnet-group-name $SID-data-subnets --db-subnet-group-description "app subnets" \
  --subnet-ids ${APP_SUBNETS//,/ } --tags $T --query 'DBSubnetGroup.SubnetGroupStatus' --output text

echo "== 1-3 파라미터 그룹 2개"
aws rds create-db-cluster-parameter-group --db-cluster-parameter-group-name $SID-data-cpg --db-parameter-group-family aurora-postgresql17 \
  --description "opslab data cluster parameters" --tags $T --query 'DBClusterParameterGroup.DBClusterParameterGroupName' --output text
aws rds create-db-parameter-group --db-parameter-group-name $SID-data-ipg --db-parameter-group-family aurora-postgresql17 \
  --description "opslab data instance parameters" --tags $T --query 'DBParameterGroup.DBParameterGroupName' --output text

echo "== 1-4 Aurora 클러스터와 인스턴스 2대 (10~15분)"
ADMIN_PW="Adm-$(openssl rand -hex 12)"
aws ssm put-parameter --name /opslab/data/admin_password --type String --overwrite --value "$ADMIN_PW" >/dev/null
aws rds create-db-cluster --db-cluster-identifier $SID-data-db --engine aurora-postgresql --engine-version 17.9 \
  --database-name opslab --master-username opslab_admin --master-user-password "$ADMIN_PW" \
  --db-cluster-parameter-group-name $SID-data-cpg --db-subnet-group-name $SID-data-subnets --vpc-security-group-ids $DB_SG \
  --backup-retention-period 1 --storage-encrypted --tags $T Key=Name,Value=$SID-data-db --query 'DBCluster.Status' --output text
for n in 1 2; do
  aws rds create-db-instance --db-instance-identifier $SID-data-db-$n --db-cluster-identifier $SID-data-db --engine aurora-postgresql \
    --db-instance-class db.t4g.medium --db-parameter-group-name $SID-data-ipg --promotion-tier 1 \
    --tags $T Key=Name,Value=$SID-data-db-$n --query 'DBInstance.DBInstanceStatus' --output text
done
aws rds wait db-instance-available --db-instance-identifier $SID-data-db-1
aws rds wait db-instance-available --db-instance-identifier $SID-data-db-2
aws rds describe-db-clusters --db-cluster-identifier $SID-data-db \
  --query 'DBClusters[0].{Writer:Endpoint,Reader:ReaderEndpoint,Members:DBClusterMembers[].[DBInstanceIdentifier,IsClusterWriter]}'

echo "== 1-5 앱 접속정보 (SSM Parameter Store)"
read -r EP REP <<<"$(aws rds describe-db-clusters --db-cluster-identifier $SID-data-db --query 'DBClusters[0].[Endpoint,ReaderEndpoint]' --output text)"
P=/opslab/app/db
aws ssm put-parameter --name $P/host        --type String --overwrite --value "$EP"  >/dev/null
aws ssm put-parameter --name $P/reader_host --type String --overwrite --value "$REP" >/dev/null
aws ssm put-parameter --name $P/port        --type String --overwrite --value 5432    >/dev/null
aws ssm put-parameter --name $P/name        --type String --overwrite --value opslab  >/dev/null
aws ssm put-parameter --name $P/user        --type String --overwrite --value app     >/dev/null
aws ssm put-parameter --name $P/password    --type String --overwrite --value "App-$(openssl rand -hex 12)" >/dev/null
aws ssm get-parameters-by-path --path $P --query 'Parameters[].[Name,Value]' --output table

echo "== 1-6 앱 계정과 테이블"
bash ~/opslab/layers/l3-data.init.sh

echo "== 1-7 재발 방지: 복제 지연·연결 수 알람"
aws cloudwatch put-metric-alarm --alarm-name $SID-data-replica-lag --namespace AWS/RDS --metric-name AuroraReplicaLagMaximum \
  --dimensions Name=DBClusterIdentifier,Value=$SID-data-db --statistic Maximum --period 60 --evaluation-periods 2 --threshold 1000 \
  --comparison-operator GreaterThanOrEqualToThreshold --treat-missing-data notBreaching --tags $T
aws cloudwatch put-metric-alarm --alarm-name $SID-data-connections --namespace AWS/RDS --metric-name DatabaseConnections \
  --dimensions Name=DBClusterIdentifier,Value=$SID-data-db Name=Role,Value=WRITER --statistic Maximum --period 60 --evaluation-periods 2 \
  --threshold 300 --comparison-operator GreaterThanOrEqualToThreshold --treat-missing-data notBreaching --tags $T

echo "== 1-8 동작 확인 (앱이 접속정보를 받는 데 최대 30초)"
sleep 40
for i in 1 2 3; do curl -s http://$ALB_DNS/db; echo; done
curl -s "http://$ALB_DNS/db?ro=1"; echo
echo "✅ 1단계 명령 완료"
