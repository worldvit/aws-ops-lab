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
if aws rds describe-db-clusters --db-cluster-identifier "$SID-rel-restore" >/dev/null 2>&1; then
  aws rds delete-db-instance --db-instance-identifier "$SID-rel-restore-1" >/dev/null 2>&1
  aws rds wait db-instance-deleted --db-instance-identifier "$SID-rel-restore-1" 2>/dev/null
  aws rds delete-db-cluster --db-cluster-identifier "$SID-rel-restore" --skip-final-snapshot >/dev/null 2>&1 && echo "  복원 훈련 클러스터 삭제 요청"
fi
for s in $(aws rds describe-db-cluster-snapshots --snapshot-type manual --query "DBClusterSnapshots[?starts_with(DBClusterSnapshotIdentifier,'$SID-rel-')].DBClusterSnapshotIdentifier" --output text); do
  aws rds delete-db-cluster-snapshot --db-cluster-snapshot-identifier "$s" >/dev/null && echo "  스냅샷 삭제: $s"; done
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
