#!/bin/bash
# iac 모듈 정리 훅 — common/cleanup.sh 가 스택을 지우기 전에 호출한다.
# · 롤백 교착(UPDATE_ROLLBACK_FAILED) 스택은 지울 수 없으므로 의존 설정을 고치고 롤백을 마저 끝낸다(안 되면 사전 점검 건너뛰기)
# · <학번>-iac-app 스택 삭제(버킷은 Retain 이라 남음) → 산출물 버킷(<학번>-iac-artifacts-*)을 모든 버전까지 비우고 삭제
# · 수동 SG(<학번>-iac-admin-sg-v2, -new), SSM 문서, SSM /opslab/iac/*, Lambda 로그 그룹
set -uo pipefail
: "${SID:?}"; export AWS_REGION="${AWS_REGION:-ap-northeast-2}"
S="$SID-iac-app"
st=$(aws cloudformation describe-stacks --stack-name "$S" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo NONE)
if [ "$st" = UPDATE_ROLLBACK_FAILED ]; then
  aws ssm put-parameter --name /opslab/iac/dependency --type String --overwrite --value ready >/dev/null 2>&1
  aws cloudformation continue-update-rollback --stack-name "$S" --resources-to-skip PreCheck 2>/dev/null
  aws cloudformation wait stack-rollback-complete --stack-name "$S" 2>/dev/null; echo "  롤백 교착 해소"
fi
if [ "$st" != NONE ]; then
  aws cloudformation delete-stack --stack-name "$S" && aws cloudformation wait stack-delete-complete --stack-name "$S" && echo "  스택 삭제: $S"
fi
for b in $(aws s3api list-buckets --query "Buckets[?starts_with(Name,'$SID-iac-artifacts-')].Name" --output text); do
  python3 - "$b" <<'PY'
import sys, boto3
b = boto3.resource("s3").Bucket(sys.argv[1]); b.object_versions.delete(); b.delete()
PY
  echo "  버킷 삭제: $b"
done
for n in v2 new; do   # 장애 스크립트가 만든 수동 SG(iac-2: -v2, iac-3: -new)
  sg=$(aws ec2 describe-security-groups --filters Name=group-name,Values="$SID-iac-admin-sg-$n" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
  [ -n "$sg" ] && [ "$sg" != None ] && aws ec2 delete-security-group --group-id "$sg" 2>/dev/null && echo "  수동 SG 삭제: $SID-iac-admin-sg-$n"
done
aws ssm delete-document --name "$SID-iac-restart-app" 2>/dev/null && echo "  SSM 문서 삭제"
N=$(aws ssm get-parameters-by-path --path /opslab/iac --query 'Parameters[].Name' --output text)
[ -n "${N// /}" ] && aws ssm delete-parameters --names $N >/dev/null && echo "  SSM /opslab/iac/* 삭제"
# 콘솔 "지금 패치 적용"이 남기는 연결(AWS-PatchNowAssociation) — 대상이 내 앱 서버 태그인 것만
for a in $(aws ssm list-associations --association-filter-list key=AssociationName,value=AWS-PatchNowAssociation \
            --query "Associations[?Targets[?contains(Values,'$SID-cmp-app')]].AssociationId" --output text 2>/dev/null); do
  aws ssm delete-association --association-id "$a" && echo "  지금 패치 적용 연결 삭제: $a"
done
aws logs delete-log-group --log-group-name "/aws/lambda/$SID-iac-precheck" 2>/dev/null && echo "  Lambda 로그 그룹 삭제"
exit 0
