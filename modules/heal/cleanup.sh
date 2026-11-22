#!/bin/bash
# heal 정리 훅 — common/cleanup.sh 가 스택 삭제 전에 부른다. FIS 실험·템플릿(heal)을 지운다.
# (노드 그룹 크기·자동 복구 설정은 K1 스택과 함께, IRSA 역할은 공통 정리의 CLI 역할 정리가 지운다)
set -uo pipefail
: "${SID:?}"; export AWS_REGION="${AWS_REGION:-ap-northeast-2}"
for e in $(aws fis list-experiments --query "experiments[?state.status=='running' && tags.Module=='heal' && tags.Owner=='$SID'].id" --output text 2>/dev/null); do
  aws fis stop-experiment --id "$e" >/dev/null 2>&1 && echo "  FIS 실험 중지: $e"; done
for t in $(aws fis list-experiment-templates --query "experimentTemplates[?tags.Module=='heal' && tags.Owner=='$SID'].id" --output text 2>/dev/null); do
  aws fis delete-experiment-template --id "$t" >/dev/null 2>&1 && echo "  FIS 실험 템플릿 삭제: $t"; done
exit 0
