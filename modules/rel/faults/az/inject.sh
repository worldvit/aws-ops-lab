#!/bin/bash
# rel az — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: v1 ASG 서브넷 목록(AZ-a 만) + 다른 AZ 서버 교체, v2 DB 라이터를 AZ-a 로 장애 조치. 그 뒤 FIS 로 AZ-a 앱·DB 서브넷 15분 단절(NACL 교체, 자동 원복).
#           주입 전용 실험 템플릿 <학번>-rel-az-fault 를 만든다(수강생 훈련 템플릿은 건드리지 않음).
AZA=$(az_of "$SUB_A"); [ -n "$AZA" ] || exit 3
save subnets "$(asg_subnets | tr ' ' ',')"
V_=$(pick_variant 2)
case $V_ in
  1) # 비용·관리 편의로 Auto Scaling 그룹을 한 AZ(a) 서브넷만 쓰게 바꿈 → 서버가 모두 AZ-a 로 모임
     aws autoscaling update-auto-scaling-group --auto-scaling-group-name "$ASG" --vpc-zone-identifier "$SUB_A" || exit 1
     for i in $(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" --query "AutoScalingGroups[0].Instances[?AvailabilityZone!='$AZA'].InstanceId" --output text); do
       aws autoscaling terminate-instance-in-auto-scaling-group --instance-id "$i" --no-should-decrement-desired-capacity >/dev/null; done
     for n in $(seq 1 40); do c=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" --query "length(AutoScalingGroups[0].Instances[?LifecycleState=='InService' && AvailabilityZone=='$AZA'])" --output text)
       t=$(aws elbv2 describe-target-health --target-group-arn "$(aws elbv2 describe-target-groups --names $SID-cmp-tg --query 'TargetGroups[0].TargetGroupArn' --output text)" --query "length(TargetHealthDescriptions[?TargetHealth.State=='healthy'])" --output text)
       [ "$c" -ge 2 ] && [ "$t" -ge 2 ] && break; sleep 15; done ;;
  2) # DB 라이터가 AZ-a 에 있는 상태(장애 조치로 옮김)
     if [ "$(writer_az)" != "$AZA" ]; then
       T=$(aws rds describe-db-instances --filters Name=db-cluster-id,Values="$CLUSTER" --query "DBInstances[?AvailabilityZone=='$AZA'].DBInstanceIdentifier|[0]" --output text)
       aws rds failover-db-cluster --db-cluster-identifier "$CLUSTER" --target-db-instance-identifier "$T" >/dev/null || exit 1
       sleep 60; wait_cluster 600
     fi ;;
esac
# AZ-a 단절 15분 (DB 장애 조치 동작 없음 — 네트워크만 끊긴 장애는 Aurora 가 스스로 넘기지 않는다)
TJ=$(jq -nc --arg role "arn:aws:iam::$ACCT:role/opslab-fis" --arg sub "arn:aws:ec2:$AWS_REGION:$ACCT:subnet/$SUB_A" --arg sid "$SID" '{
  description:"opslab rel-2 fault: AZ-a app/db subnet outage 15 min", roleArn:$role, stopConditions:[{source:"none"}],
  targets:{subnetA:{resourceType:"aws:ec2:subnet",resourceArns:[$sub],selectionMode:"ALL"}},
  actions:{cutAzA:{actionId:"aws:network:disrupt-connectivity",parameters:{duration:"PT15M",scope:"all"},targets:{Subnets:"subnetA"}}},
  tags:{Name:($sid+"-rel-az-fault"),Course:"opslab",Module:"rel",Owner:$sid}}')
TID=$(aws fis create-experiment-template --cli-input-json "$TJ" --query experimentTemplate.id --output text) || exit 1
save template "$TID"
EID=$(aws fis start-experiment --experiment-template-id "$TID" --tags Name=$SID-rel-az-fault,Course=opslab,Module=rel,Owner=$SID --query experiment.id --output text) || exit 1
save experiment "$EID"
record $V_
