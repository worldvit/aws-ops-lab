#!/bin/bash
# data 모듈 정리 훅 — 수강생이 CLI로 직접 만든 data 리소스를 지운다. common/cleanup.sh 가 스택을 지우기 전에 호출한다.
# 순서: 복원 연습 클러스터(항상) → (L3 스택이 없을 때) 인스턴스 → 클러스터 → 파라미터 그룹·서브넷 그룹·보안 그룹 → SSM 접속정보
set -uo pipefail
: "${SID:?}"; export AWS_REGION="${AWS_REGION:-ap-northeast-2}"
del_cluster() {  # $1=클러스터 ID — 인스턴스부터 지우고 클러스터 삭제, 끝날 때까지 기다린다
  local c=$1 i
  for i in $(aws rds describe-db-instances --filters Name=db-cluster-id,Values="$c" --query 'DBInstances[].DBInstanceIdentifier' --output text); do
    aws rds delete-db-instance --db-instance-identifier "$i" --skip-final-snapshot >/dev/null 2>&1 && echo "  DB 인스턴스 삭제 요청: $i"
  done
  for i in $(aws rds describe-db-instances --filters Name=db-cluster-id,Values="$c" --query 'DBInstances[].DBInstanceIdentifier' --output text); do
    aws rds wait db-instance-deleted --db-instance-identifier "$i" 2>/dev/null
  done
  aws rds delete-db-cluster --db-cluster-identifier "$c" --skip-final-snapshot >/dev/null 2>&1 && echo "  DB 클러스터 삭제 요청: $c (5~10분)"
  for _ in $(seq 1 60); do aws rds describe-db-clusters --db-cluster-identifier "$c" >/dev/null 2>&1 || break; sleep 15; done
}

# 1) PITR 연습으로 만든 복원 클러스터(이름 <학번>-data-restore*)
for c in $(aws rds describe-db-clusters --query "DBClusters[?starts_with(DBClusterIdentifier,'$SID-data-restore')].DBClusterIdentifier" --output text 2>/dev/null); do
  del_cluster "$c"
done

# 2) L3 스택이 있으면 나머지는 스택 삭제가 처리
aws cloudformation describe-stacks --stack-name "$SID-l3" >/dev/null 2>&1 && { echo "  L3 층 스택($SID-l3)이 있어 나머지는 스택 삭제로 정리"; exit 0; }

# 3) 수강생이 만든 클러스터와 주변 리소스
aws rds describe-db-clusters --db-cluster-identifier "$SID-data-db" >/dev/null 2>&1 && del_cluster "$SID-data-db"
for g in $(aws rds describe-db-cluster-parameter-groups --query "DBClusterParameterGroups[?starts_with(DBClusterParameterGroupName,'$SID-data-')].DBClusterParameterGroupName" --output text); do
  aws rds delete-db-cluster-parameter-group --db-cluster-parameter-group-name "$g" 2>/dev/null && echo "  클러스터 파라미터 그룹 삭제: $g"
done
for g in $(aws rds describe-db-parameter-groups --query "DBParameterGroups[?starts_with(DBParameterGroupName,'$SID-data-')].DBParameterGroupName" --output text); do
  aws rds delete-db-parameter-group --db-parameter-group-name "$g" 2>/dev/null && echo "  인스턴스 파라미터 그룹 삭제: $g"
done
aws rds delete-db-subnet-group --db-subnet-group-name "$SID-data-subnets" 2>/dev/null && echo "  DB 서브넷 그룹 삭제"
sg=$(aws ec2 describe-security-groups --filters Name=group-name,Values="$SID-data-db-sg" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
if [ -n "$sg" ] && [ "$sg" != None ]; then
  for _ in $(seq 1 12); do aws ec2 delete-security-group --group-id "$sg" >/dev/null 2>&1 && { echo "  SG 삭제: $SID-data-db-sg"; break; }; sleep 10; done
fi
N=$(aws ssm get-parameters-by-path --path /opslab/app/db --query 'Parameters[].Name' --output text; aws ssm get-parameters-by-path --path /opslab/data --query 'Parameters[].Name' --output text)
[ -n "${N// /}" ] && aws ssm delete-parameters --names $N >/dev/null && echo "  SSM 접속정보 삭제"
exit 0
