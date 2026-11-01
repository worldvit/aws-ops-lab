#!/bin/bash
# rel cost — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: v1 ASG 크기, v2 EC2 1대(t3.xlarge)+EBS 200GB, v3 NAT 게이트웨이 1개+탄력적 IP 2개. 모두 태그 Course=opslab·Module=rel·Owner 를 단다.
#           서비스는 정상이다. 시간당 약 $0.1~0.2 가 더 든다.
save size "$(asg_size)"
V_=$(pick_variant 3)
TS="ResourceType=%s,Tags=[{Key=Name,Value=%s},{Key=Course,Value=opslab},{Key=Module,Value=rel},{Key=Owner,Value=$SID}]"
case $V_ in
  1) # 행사 트래픽 대비로 최소·희망 6대, 최대 8대로 올리고 되돌리지 않음
     aws autoscaling update-auto-scaling-group --auto-scaling-group-name "$ASG" --min-size 6 --desired-capacity 6 --max-size 8 || exit 1 ;;
  2) # 배치 작업용으로 큰 서버와 데이터 볼륨을 만들고 작업이 끝난 뒤 방치
     AMI=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query Parameter.Value --output text)
     aws ec2 run-instances --image-id "$AMI" --instance-type t3.xlarge --subnet-id "$SUB_C"        --tag-specifications "$(printf "$TS" instance $SID-rel-batch)" "$(printf "$TS" volume $SID-rel-batch)" --query 'Instances[0].InstanceId' --output text >/dev/null || exit 1
     aws ec2 create-volume --availability-zone "$(az_of $SUB_C)" --size 200 --volume-type gp3        --tag-specifications "$(printf "$TS" volume $SID-rel-batch-data)" --query VolumeId --output text >/dev/null || exit 1 ;;
  3) # 이중화 시험용 NAT 게이트웨이(AZ-c)와 예비 IP 를 만들고 연결하지 않은 채 방치
     PUBC=$(aws cloudformation list-exports --query "Exports[?Name=='$SID-base-PublicSubnets'].Value" --output text | cut -d, -f2)
     E1=$(aws ec2 allocate-address --domain vpc --tag-specifications "$(printf "$TS" elastic-ip $SID-rel-nat-eip)" --query AllocationId --output text) || exit 1
     aws ec2 allocate-address --domain vpc --tag-specifications "$(printf "$TS" elastic-ip $SID-rel-spare-eip)" --query AllocationId --output text >/dev/null || exit 1
     aws ec2 create-nat-gateway --subnet-id "$PUBC" --allocation-id "$E1" --tag-specifications "$(printf "$TS" natgateway $SID-rel-nat-c)" --query NatGateway.NatGatewayId --output text >/dev/null || exit 1 ;;
esac
record $V_
