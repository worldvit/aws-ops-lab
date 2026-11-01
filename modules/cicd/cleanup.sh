#!/bin/bash
# cicd 정리 훅 — common/cleanup.sh 가 스택 삭제 전에 부른다. 수강생이 CLI 로 만든 것과 파이프라인이 만든 것을 지운다.
# · 파이프라인, CodeBuild 프로젝트, CodeDeploy 앱 2개(배포 그룹 포함), 릴리스 스택, 소스 연결, 산출물 버킷 내용(모든 버전),
#   CodeBuild 로그 그룹, 작업 정의 등록 해제, SSM /opslab/cicd/*
set -uo pipefail
: "${SID:?}"; export AWS_REGION="${AWS_REGION:-ap-northeast-2}"
aws codepipeline get-pipeline --name "$SID-cicd-pipeline" >/dev/null 2>&1 && aws codepipeline delete-pipeline --name "$SID-cicd-pipeline" && echo "  파이프라인 삭제"
[ "$(aws codebuild batch-get-projects --names "$SID-cicd-build" --query 'length(projects)' --output text 2>/dev/null)" = 1 ] && aws codebuild delete-project --name "$SID-cicd-build" >/dev/null && echo "  CodeBuild 프로젝트 삭제"
for a in "$SID-cicd-ec2" "$SID-cicd-ecs"; do aws deploy get-application --application-name "$a" >/dev/null 2>&1 && aws deploy delete-application --application-name "$a" && echo "  CodeDeploy 앱 삭제: $a"; done
if aws cloudformation describe-stacks --stack-name "$SID-cicd-release" >/dev/null 2>&1; then
  aws cloudformation delete-stack --stack-name "$SID-cicd-release"; aws cloudformation wait stack-delete-complete --stack-name "$SID-cicd-release"; echo "  릴리스 스택 삭제"
fi
for c in $(aws codeconnections list-connections --query "Connections[?ConnectionName=='$SID-cicd-github'].ConnectionArn" --output text 2>/dev/null); do
  aws codeconnections delete-connection --connection-arn "$c" >/dev/null && echo "  소스 연결 삭제"; done
B="$SID-cicd-artifacts-$(aws sts get-caller-identity --query Account --output text)"
if aws s3api head-bucket --bucket "$B" 2>/dev/null; then
  python3 - "$B" <<'PY'
import sys, boto3
boto3.resource("s3").Bucket(sys.argv[1]).object_versions.delete()
PY
  echo "  산출물 버킷 비움: $B (버킷은 스택이 삭제)"
fi
aws logs delete-log-group --log-group-name "/aws/codebuild/$SID-cicd-build" 2>/dev/null && echo "  CodeBuild 로그 그룹 삭제"
for td in $(aws ecs list-task-definitions --family-prefix "$SID-cicd-app" --status ACTIVE --query 'taskDefinitionArns[]' --output text 2>/dev/null); do
  aws ecs deregister-task-definition --task-definition "$td" >/dev/null; done
N=$(aws ssm get-parameters-by-path --path /opslab/cicd --recursive --query 'Parameters[].Name' --output text)
[ -n "${N// /}" ] && aws ssm delete-parameters --names $N >/dev/null && echo "  SSM /opslab/cicd/* 삭제"
# 장애 실습이 역할에 붙인 거부 정책(opslab-fault-deny)이 남아 있으면 역할(스택) 삭제가 실패한다 — 먼저 지운다
for r in pipeline build deploy cfn task-exec; do aws iam delete-role-policy --role-name "$SID-cicd-$r-role" --policy-name opslab-fault-deny 2>/dev/null && echo "  거부 정책 삭제: $SID-cicd-$r-role"; done
aws iam delete-role-policy --role-name "$SID-base-ec2-role" --policy-name opslab-fault-deny 2>/dev/null && echo "  거부 정책 삭제: $SID-base-ec2-role"
# 콘솔 CodeBuild 의 "서비스 역할 수정" 체크를 해제하지 않았으면 콘솔이 빌드 역할에 CodeBuildBasePolicy-<프로젝트>-<리전> 을 만들어 붙인다
#   → 붙어 있으면 역할(스택) 삭제가 실패하므로 떼고 정책도 지운다
for p in $(aws iam list-attached-role-policies --role-name "$SID-cicd-build-role" \
            --query "AttachedPolicies[?starts_with(PolicyName,'CodeBuildBasePolicy-')].PolicyArn" --output text 2>/dev/null); do
  aws iam detach-role-policy --role-name "$SID-cicd-build-role" --policy-arn "$p" && echo "  콘솔이 붙인 정책 분리: ${p##*/}"
  for v in $(aws iam list-policy-versions --policy-arn "$p" --query 'Versions[?!IsDefaultVersion].VersionId' --output text 2>/dev/null); do
    aws iam delete-policy-version --policy-arn "$p" --version-id "$v"; done
  aws iam delete-policy --policy-arn "$p" 2>/dev/null && echo "  정책 삭제: ${p##*/}"
done
exit 0
