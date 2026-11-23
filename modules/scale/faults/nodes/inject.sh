#!/bin/bash
# scale-2 nodes — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: Karpenter NodePool·EC2NodeClass(default), 배치 작업 파드(opslab-batch — CPU 1개씩 3개)
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 3)
case $V in
  1) # "비용 상한"을 걸며 NodePool 자원 한도를 cpu 1 로 — 어떤 인스턴스도 한도 안에 들지 못한다
     kubectl patch nodepool default --type merge -p '{"spec":{"limits":{"cpu":"1"}}}' >/dev/null ;;
  2) # "작은 인스턴스만 쓰자"며 크기 조건을 medium 으로 — CPU 1개를 요청하는 파드가 들어갈 인스턴스가 없다
     I=$(np_json | jq '[.spec.template.spec.requirements[].key] | index("karpenter.k8s.aws/instance-size")')
     kubectl patch nodepool default --type json -p "[{\"op\":\"replace\",\"path\":\"/spec/template/spec/requirements/$I/values\",\"value\":[\"medium\"]}]" >/dev/null ;;
  3) # 서브넷 태그 정리 계획에 맞춰 EC2NodeClass 의 서브넷 선택 태그를 새 값으로 먼저 바꿨다 — 그런 태그의 서브넷이 없다
     kubectl patch ec2nodeclass default --type merge -p "{\"spec\":{\"subnetSelectorTerms\":[{\"tags\":{\"karpenter.sh/discovery\":\"$SID-private\"}}]}}" >/dev/null ;;
esac
sleep 5
batch start 3 1      # 이벤트 시작 — 야간 배치 작업(CPU 1개씩 3개)
record $V
