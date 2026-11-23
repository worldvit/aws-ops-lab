#!/bin/bash
# scale 정리 훅 — common/cleanup.sh 가 스택 삭제 전에 부른다.
#   ① 실습용 Deployment ② 스냅샷(EBS 스냅샷까지) ③ Karpenter: NodePool → 노드 → EC2NodeClass → 컨트롤러, 시작 템플릿·인스턴스 프로파일
#   ④ 클러스터 오토스케일러 ⑤ IRSA 역할 — Karpenter 를 지우지 않고 클러스터부터 지우면 Karpenter 가 만든 EC2 가 남는다
set -uo pipefail
: "${SID:?}"; export AWS_REGION="${AWS_REGION:-ap-northeast-2}"
source "$(dirname "$(readlink -f "$0")")/../../common/eks.sh"
source "$EKS_ROOT/modules/scale/functions.sh"
if kube_login >/dev/null 2>&1; then
  kubectl -n "$APP_NS" delete deploy opslab-spike opslab-batch opslab-cache-worker opslab-idle --ignore-not-found --wait=false >/dev/null 2>&1
  kubectl -n "$APP_NS" delete volumesnapshot --all --timeout=120s >/dev/null 2>&1 && echo "  스냅샷(VolumeSnapshot·EBS 스냅샷) 삭제"
  kp_cleanup && echo "  Karpenter NodePool·노드·EC2NodeClass 삭제"
  helm -n kube-system uninstall karpenter >/dev/null 2>&1 && echo "  Karpenter 컨트롤러 삭제"
  helm -n kube-system uninstall cluster-autoscaler >/dev/null 2>&1 && echo "  클러스터 오토스케일러 삭제"
fi
# 남은 Karpenter EC2·시작 템플릿·인스턴스 프로파일(컨트롤러가 먼저 지워졌을 때)
ids=$(aws ec2 describe-instances --filters "Name=tag:karpenter.sh/nodepool,Values=*" "Name=tag:Owner,Values=$SID" "Name=instance-state-name,Values=pending,running,stopping,stopped" --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null)
[ -n "$ids" ] && aws ec2 terminate-instances --instance-ids $ids >/dev/null && echo "  남은 Karpenter 노드 종료: $ids" && aws ec2 wait instance-terminated --instance-ids $ids
for lt in $(aws ec2 describe-launch-templates --filters "Name=tag:karpenter.k8s.aws/cluster,Values=$CLUSTER" --query 'LaunchTemplates[].LaunchTemplateId' --output text 2>/dev/null); do
  aws ec2 delete-launch-template --launch-template-id "$lt" >/dev/null && echo "  Karpenter 시작 템플릿 삭제: $lt"; done
for ip in $(aws iam list-instance-profiles-for-role --role-name "$NODE_ROLE" --query 'InstanceProfiles[].InstanceProfileName' --output text 2>/dev/null); do
  case "$ip" in eks-*) continue ;; esac   # 관리형 노드 그룹이 만든 것은 EKS 가 지운다
  aws iam remove-role-from-instance-profile --instance-profile-name "$ip" --role-name "$NODE_ROLE" >/dev/null 2>&1
  aws iam delete-instance-profile --instance-profile-name "$ip" >/dev/null 2>&1 && echo "  Karpenter 인스턴스 프로파일 삭제: $ip"; done
for r in "$KP_ROLE" "$CA_ROLE"; do
  aws iam delete-role-policy --role-name "$r" --policy-name scale >/dev/null 2>&1
  aws iam delete-role --role-name "$r" >/dev/null 2>&1 && echo "  IRSA 역할 삭제: $r"; done
exit 0
