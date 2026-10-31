#!/bin/bash
# sec 모듈 정리 훅 — common/cleanup.sh 가 스택을 지우기 전에 호출한다.
# · Secrets Manager 비밀은 지우면 기본 7~30일 "삭제 예정"으로 남아 다음 날 같은 이름을 못 쓴다 → 즉시 삭제
# · L4 스택이 없을 때(수강생이 CLI로 구축): KMS 키(7일 뒤 삭제 예약)·별칭, Vault EC2, 보안 그룹, 앱 역할 인라인 정책
# · SSM /opslab/sec/* (Vault 주소·키 조각·root 토큰) — 남아 있으면 다음 날 새 앱 서버가 없는 Vault 를 찾는다
set -uo pipefail
: "${SID:?}"; export AWS_REGION="${AWS_REGION:-ap-northeast-2}"
aws secretsmanager describe-secret --secret-id "$SID/sec/app" >/dev/null 2>&1 && \
  aws secretsmanager delete-secret --secret-id "$SID/sec/app" --force-delete-without-recovery >/dev/null && echo "  비밀 즉시 삭제: $SID/sec/app"
if ! aws cloudformation describe-stacks --stack-name "$SID-l4" >/dev/null 2>&1; then
  K=$(aws kms describe-key --key-id "alias/$SID-sec-key" --query KeyMetadata.KeyId --output text 2>/dev/null)
  if [ -n "$K" ] && [ "$K" != None ]; then
    aws kms delete-alias --alias-name "alias/$SID-sec-key" 2>/dev/null
    aws kms schedule-key-deletion --key-id "$K" --pending-window-in-days 7 >/dev/null 2>&1 && echo "  KMS 키 삭제 예약(7일): $K"
  fi
  aws iam delete-role-policy --role-name "$SID-base-ec2-role" --policy-name "$SID-sec-app-access" 2>/dev/null && echo "  앱 역할 인라인 정책 삭제"
  V=$(aws ec2 describe-instances --filters Name=tag:Name,Values="$SID-sec-vault" Name=instance-state-name,Values=pending,running,stopping,stopped \
       --query 'Reservations[].Instances[].InstanceId' --output text)
  [ -n "$V" ] && aws ec2 terminate-instances --instance-ids $V >/dev/null && echo "  Vault EC2 종료: $V" && aws ec2 wait instance-terminated --instance-ids $V
  sg=$(aws ec2 describe-security-groups --filters Name=group-name,Values="$SID-sec-vault-sg" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
  [ -n "$sg" ] && [ "$sg" != None ] && aws ec2 delete-security-group --group-id "$sg" 2>/dev/null && echo "  SG 삭제: $SID-sec-vault-sg"
fi
N=$(aws ssm get-parameters-by-path --path /opslab/sec --recursive --query 'Parameters[].Name' --output text)
[ -n "${N// /}" ] && aws ssm delete-parameters --names $N >/dev/null && echo "  SSM /opslab/sec/* 삭제"
exit 0
