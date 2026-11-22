#!/bin/bash
# heal-3 disrupt — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: 운영 값 파일 커밋(pdb·topology·nodeSelector), 노드 cordon·앱 파드만 드레인(--pod-selector), FIS 실험(③ 앱 파드가 모인 AZ 의 앱 서브넷 5분 단절)
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 3); base_save
SEL=app.kubernetes.io/instance=opslab-app
case $V in
  1) # "PDB 정리" 커밋 뒤, 점검 담당자가 앱 파드가 있는 노드 2대를 동시에 비웠다
     commit "쓰지 않는 PDB 정리" '/^pdb:/,/^  minAvailable:/ s/^  enabled: true/  enabled: false/'
     for i in $(seq 1 36); do pdb_json >/dev/null || break; [ $((i % 6)) -eq 0 ] && kick; sleep 5; done
     pdb_json >/dev/null && { echo "PDB 가 지워지지 않았습니다"; exit 1; }
     NODES=$(app_nodes | head -2); save drained "$(echo $NODES)"
     for n in $NODES; do kubectl drain "$n" --pod-selector="$SEL" --delete-emptydir-data --timeout=120s >/dev/null 2>&1 & done; wait ;;
  2) # "가용성 강화"로 minAvailable 을 파드 수(2)와 같게 → 노드 점검(드레인)이 끝나지 않는다
     commit "가용성 강화: 최소 2개 유지" '/^pdb:/,/^  minAvailable:/ s/^  minAvailable: 1/  minAvailable: 2/'
     for i in $(seq 1 36); do [ "$(pdb_json | jq -r '.spec.minAvailable')" = 2 ] && break; [ $((i % 6)) -eq 0 ] && kick; sleep 5; done
     N=$(app_nodes | head -1); save drained "$N"
     kubectl drain "$N" --pod-selector="$SEL" --delete-emptydir-data --timeout=90s >/dev/null 2>&1 || true ;;
  3) # "AZ 간 전송 비용 절감"으로 파드를 한 AZ 에 모았다(분산 규칙 삭제 + AZ 고정) → 그 AZ 가 5분 동안 끊긴다
     PZ=$(node_zone "$(pg_node)")
     Z=$(kubectl get nodes -o json | jq -r --arg p "$PZ" '[.items[].metadata.labels["topology.kubernetes.io/zone"]] | map(select(. != $p)) | sort | .[0]')
     commit "AZ 간 전송 비용 절감: 파드를 $Z 에 모음" "/^topologySpreadConstraints:/,/^    labelSelector:/d; s/^hpa:/nodeSelector:\n  topology.kubernetes.io\/zone: $Z\nhpa:/"
     wait_rev '.spec.template.spec.nodeSelector["topology.kubernetes.io/zone"] != null'
     ro_wait 900
     SUB=$(aws ec2 describe-subnets --subnet-ids $(aws cloudformation list-exports --query "Exports[?Name=='$SID-base-AppSubnets'].Value" --output text | tr ',' ' ') \
           --query "Subnets[?AvailabilityZone=='$Z'].SubnetId | [0]" --output text)
     TJ=$(jq -nc --arg role "arn:aws:iam::$ACCT:role/opslab-fis" --arg sub "arn:aws:ec2:$AWS_REGION:$ACCT:subnet/$SUB" --arg sid "$SID" '{
       description:"opslab heal-3 fault: one AZ app subnet outage 5 min", roleArn:$role, stopConditions:[{source:"none"}],
       targets:{azSubnet:{resourceType:"aws:ec2:subnet",resourceArns:[$sub],selectionMode:"ALL"}},
       actions:{cutAz:{actionId:"aws:network:disrupt-connectivity",parameters:{duration:"PT5M",scope:"all"},targets:{Subnets:"azSubnet"}}},
       tags:{Name:($sid+"-heal-az-fault"),Course:"opslab",Module:"heal",Owner:$sid}}')
     TID=$(aws fis create-experiment-template --cli-input-json "$TJ" --query experimentTemplate.id --output text)
     save template "$TID"
     aws fis start-experiment --experiment-template-id "$TID" --tags Name=$SID-heal-az-fault,Course=opslab,Module=heal,Owner=$SID --query experiment.id --output text >/dev/null ;;
esac
record $V
