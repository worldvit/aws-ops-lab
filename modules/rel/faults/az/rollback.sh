#!/bin/bash
# rel az — rollback. 진행 중인 실험 중지(NACL 원복), ASG 서브넷 두 AZ, 주입 템플릿 삭제. DB 라이터 위치는 그대로 둔다(어느 AZ 든 정상).
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
for e in $(fis_running); do aws fis stop-experiment --id "$e" >/dev/null && echo "  실험 중지: $e"; done
for i in $(seq 1 20); do [ -z "$(fis_running)" ] && break; sleep 5; done
aws autoscaling update-auto-scaling-group --auto-scaling-group-name "$ASG" --vpc-zone-identifier "$SUB_A,$SUB_C" && echo "  ASG 서브넷 두 AZ"
for t in $(aws fis list-experiment-templates --query "experimentTemplates[?tags.Name=='$SID-rel-az-fault'].id" --output text); do
  aws fis delete-experiment-template --id "$t" >/dev/null && echo "  주입 템플릿 삭제: $t"; done
# 단절 동안 비정상으로 교체된 서버가 다시 붙을 때까지
wait_inservice 2 600; exit 0
