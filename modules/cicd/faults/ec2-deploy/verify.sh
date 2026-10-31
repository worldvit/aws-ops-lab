#!/bin/bash
# cicd ec2-deploy 판정 — 배포 관련 권한 정상, 마지막 실행 성공, 두 서비스가 같은 릴리스. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start ec2-deploy
echo "[1] 권한"
aws iam list-attached-role-policies --role-name "$SID-cicd-deploy-role" --query 'AttachedPolicies[].PolicyName' --output text | grep -qw AWSCodeDeployRole \
  && ok "배포 역할에 AWSCodeDeployRole 연결" || ng "배포 역할에 AWSCodeDeployRole 없음"
n=$(aws iam list-role-policies --role-name "$SID-base-ec2-role" --query "length(PolicyNames[?@=='opslab-fault-deny'])" --output text)
[ "$n" = 0 ] && ok "앱 서버 역할에 산출물 거부 정책 없음" || ng "앱 서버 역할에 거부 정책(opslab-fault-deny) 있음"
echo "[2] 파이프라인"; chk_last
echo "[3] 서비스"; chk_version
finish
