#!/bin/bash
# rel cost — rollback. ASG 2/2/4, Module=rel 태그의 EC2·볼륨·NAT·탄력적 IP 삭제.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
aws autoscaling update-auto-scaling-group --auto-scaling-group-name "$ASG" --min-size 2 --desired-capacity 2 --max-size 4 && echo "  ASG 2/2/4"
I=$(aws ec2 describe-instances --filters Name=tag:Owner,Values="$SID" Name=tag:Module,Values=rel Name=instance-state-name,Values=pending,running,stopping,stopped --query 'Reservations[].Instances[].InstanceId' --output text)
[ -n "$I" ] && aws ec2 terminate-instances --instance-ids $I >/dev/null && echo "  EC2 종료: $I"
for v in $(aws ec2 describe-volumes --filters Name=tag:Owner,Values="$SID" Name=tag:Module,Values=rel Name=status,Values=available --query 'Volumes[].VolumeId' --output text); do
  aws ec2 delete-volume --volume-id "$v" && echo "  볼륨 삭제: $v"; done
N=$(aws ec2 describe-nat-gateways --filter Name=tag:Owner,Values="$SID" Name=tag:Module,Values=rel Name=state,Values=available,pending --query 'NatGateways[].NatGatewayId' --output text)
for n in $N; do aws ec2 delete-nat-gateway --nat-gateway-id "$n" >/dev/null && echo "  NAT 삭제: $n"; done
[ -n "$N" ] && aws ec2 wait nat-gateway-deleted --nat-gateway-ids $N 2>/dev/null
# NAT 를 지운 직후에는 그 IP 가 잠시 '연결됨'으로 남는다 → 연결이 풀릴 때까지 최대 3분 반복
for i in $(seq 1 18); do
  A=$(aws ec2 describe-addresses --filters Name=tag:Owner,Values="$SID" Name=tag:Module,Values=rel --query 'Addresses[].[AllocationId,AssociationId]' --output text)
  [ -z "$A" ] && break
  while read -r a as; do [ "$as" = None ] && aws ec2 release-address --allocation-id "$a" && echo "  탄력적 IP 해제: $a"; done <<<"$A"
  sleep 10; done
exit 0
