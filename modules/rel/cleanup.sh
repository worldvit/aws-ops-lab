#!/bin/bash
# rel 모듈 정리 훅 — common/cleanup.sh 가 스택을 지우기 전에 호출한다(스택이 없는 리소스만).
# FIS 실험 중지·템플릿 삭제, S3 버킷 2개(서울·도쿄, 모든 버전), 복원 훈련 클러스터·스냅샷, Aurora 삭제 방지 해제(L3 스택 삭제용),
# 장애 주입이 남긴 EC2·볼륨·NAT·탄력적 IP(태그 Module=rel)
set -uo pipefail
: "${SID:?}"; export AWS_REGION="${AWS_REGION:-ap-northeast-2}"
ACCT=$(aws sts get-caller-identity --query Account --output text)
for e in $(aws fis list-experiments --query "experiments[?(state.status=='running' || state.status=='initiating') && tags.Owner=='$SID'].id" --output text 2>/dev/null); do
  aws fis stop-experiment --id "$e" >/dev/null && echo "  FIS 실험 중지: $e"; done
for t in $(aws fis list-experiment-templates --query "experimentTemplates[?tags.Owner=='$SID' && tags.Module=='rel'].id" --output text 2>/dev/null); do
  aws fis delete-experiment-template --id "$t" >/dev/null && echo "  FIS 템플릿 삭제: $t"; done
for b in "$SID-rel-src-$ACCT:ap-northeast-2" "$SID-rel-dr-$ACCT:ap-northeast-1"; do
  aws s3api head-bucket --bucket "${b%%:*}" --region "${b##*:}" 2>/dev/null || continue
  python3 - "${b%%:*}" "${b##*:}" <<'PY'
import sys, boto3
s3 = boto3.resource("s3", region_name=sys.argv[2]); b = s3.Bucket(sys.argv[1])
try: s3.meta.client.delete_bucket_replication(Bucket=sys.argv[1])
except Exception: pass
b.object_versions.delete(); b.delete()
PY
  echo "  버킷 삭제: ${b%%:*}"
done
# 복원 훈련 클러스터 — 이름이 무엇이든(콘솔 복원 화면은 식별자 칸에 database-1 이 미리 들어 있어 이름이 틀리기 쉽다)
# 내 DB 서브넷 그룹을 쓰는 클러스터 중 원본(<학번>-data-db)이 아닌 것을 모두 지운다. 인스턴스 이름도 제각각이라 클러스터의 모든 인스턴스를 지운다
for c in $(aws rds describe-db-clusters --query "DBClusters[?DBSubnetGroup=='$SID-data-subnets' && DBClusterIdentifier!='$SID-data-db'].DBClusterIdentifier" --output text 2>/dev/null); do
  aws rds modify-db-cluster --db-cluster-identifier "$c" --no-deletion-protection --apply-immediately >/dev/null 2>&1
  for i in $(aws rds describe-db-instances --filters Name=db-cluster-id,Values="$c" --query 'DBInstances[].DBInstanceIdentifier' --output text); do
    aws rds delete-db-instance --db-instance-identifier "$i" >/dev/null 2>&1; done
  for i in $(aws rds describe-db-instances --filters Name=db-cluster-id,Values="$c" --query 'DBInstances[].DBInstanceIdentifier' --output text); do
    aws rds wait db-instance-deleted --db-instance-identifier "$i" 2>/dev/null; done
  aws rds delete-db-cluster --db-cluster-identifier "$c" --skip-final-snapshot >/dev/null 2>&1 && echo "  복원 훈련 클러스터 삭제 요청: $c"
  for _ in $(seq 1 60); do aws rds describe-db-clusters --db-cluster-identifier "$c" >/dev/null 2>&1 || break; sleep 15; done   # L3 서브넷 그룹·SG 삭제 전에 끝나야 함
done
# 수동 스냅샷 — 이름 규칙(<학번>-rel-), 원본 클러스터의 스냅샷, 그리고 내 VPC 안의 클러스터에서 나온 스냅샷
# (콘솔에서 복원본을 지울 때 "최종 스냅샷 생성"이 기본 체크라 <복원본 이름>-final-snapshot 이 생길 수 있다)
VPC=$(aws cloudformation list-exports --query "Exports[?Name=='$SID-base-VpcId'].Value" --output text 2>/dev/null)
for s in $(aws rds describe-db-cluster-snapshots --snapshot-type manual --query "DBClusterSnapshots[?starts_with(DBClusterSnapshotIdentifier,'$SID-rel-') || DBClusterIdentifier=='$SID-data-db' || (VpcId=='${VPC:-none}' && VpcId!=null)].DBClusterSnapshotIdentifier" --output text); do
  aws rds delete-db-cluster-snapshot --db-cluster-snapshot-identifier "$s" >/dev/null && echo "  스냅샷 삭제: $s"; done
# 보존된 자동 백업 — 콘솔에서 복원본을 지울 때 "자동 백업 보존"이 기본 체크. 원본(<학번>-data-db)은 L3 스택 삭제 때 처리되므로 건드리지 않는다
for r in $(aws rds describe-db-cluster-automated-backups --query "DBClusterAutomatedBackups[?Status=='retained' && DBClusterIdentifier!='$SID-data-db' && (VpcId=='${VPC:-none}' || contains(DBClusterIdentifier,'$SID'))].DbClusterResourceId" --output text 2>/dev/null); do
  aws rds delete-db-cluster-automated-backup --db-cluster-resource-id "$r" >/dev/null 2>&1 && echo "  보존된 자동 백업 삭제: $r"; done
aws rds modify-db-cluster --db-cluster-identifier "$SID-data-db" --no-deletion-protection --apply-immediately >/dev/null 2>&1 && echo "  Aurora 삭제 방지 해제"
I=$(aws ec2 describe-instances --filters Name=tag:Owner,Values="$SID" Name=tag:Module,Values=rel Name=instance-state-name,Values=pending,running,stopping,stopped --query 'Reservations[].Instances[].InstanceId' --output text)
[ -n "$I" ] && aws ec2 terminate-instances --instance-ids $I >/dev/null && echo "  EC2 종료: $I"
N=$(aws ec2 describe-nat-gateways --filter Name=tag:Owner,Values="$SID" Name=tag:Module,Values=rel Name=state,Values=available,pending --query 'NatGateways[].NatGatewayId' --output text)
for n in $N; do aws ec2 delete-nat-gateway --nat-gateway-id "$n" >/dev/null && echo "  NAT 삭제: $n"; done
[ -n "$N" ] && aws ec2 wait nat-gateway-deleted --nat-gateway-ids $N 2>/dev/null
[ -n "$I" ] && aws ec2 wait instance-terminated --instance-ids $I 2>/dev/null
for v in $(aws ec2 describe-volumes --filters Name=tag:Owner,Values="$SID" Name=tag:Module,Values=rel Name=status,Values=available --query 'Volumes[].VolumeId' --output text); do
  aws ec2 delete-volume --volume-id "$v" && echo "  볼륨 삭제: $v"; done
for a in $(aws ec2 describe-addresses --filters Name=tag:Owner,Values="$SID" Name=tag:Module,Values=rel --query 'Addresses[?AssociationId==null].AllocationId' --output text); do
  aws ec2 release-address --allocation-id "$a" && echo "  탄력적 IP 해제: $a"; done
exit 0
