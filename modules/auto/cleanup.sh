#!/bin/bash
# auto 모듈 정리 훅 — common/cleanup.sh 가 스택을 지우기 전에 호출한다(스택이 없는 리소스만).
# EventBridge 규칙 2개, 런북 문서, 유지관리 기간, Route 53 장애 조치 레코드·헬스 체크, 로그 그룹 2개,
# Session Manager 기본 설정 문서(내 로그 그룹을 가리킬 때만 — 지우면 기본값으로 돌아감), SSM /opslab/auto/*
set -uo pipefail
: "${SID:?}"; export AWS_REGION="${AWS_REGION:-ap-northeast-2}"
for r in "$SID-auto-recover" "$SID-auto-recover-failed"; do
  ids=$(aws events list-targets-by-rule --rule "$r" --query 'Targets[].Id' --output text 2>/dev/null) || continue
  [ -n "$ids" ] && aws events remove-targets --rule "$r" --ids $ids >/dev/null
  aws events delete-rule --name "$r" && echo "  규칙 삭제: $r"
done
aws ssm delete-document --name "$SID-auto-app-recover" 2>/dev/null && echo "  런북 삭제"
for w in $(aws ssm describe-maintenance-windows --filters Key=Name,Values="$SID-auto-mw" --query 'WindowIdentities[].WindowId' --output text); do
  aws ssm delete-maintenance-window --window-id "$w" >/dev/null && echo "  유지관리 기간 삭제: $w"
done
DOM=$(aws cloudformation describe-stacks --stack-name "$SID-l0" --query "Stacks[0].Parameters[?ParameterKey=='InstructorDomain'].ParameterValue" --output text 2>/dev/null)
Z=$(aws route53 list-hosted-zones-by-name --dns-name "$SID.$DOM" --max-items 1 --query "HostedZones[?Name=='$SID.$DOM.'].Id | [0]" --output text 2>/dev/null | sed 's#/hostedzone/##')
if [ -n "$Z" ] && [ "$Z" != None ]; then
  aws route53 list-resource-record-sets --hosted-zone-id "$Z" --query "ResourceRecordSets[?Name=='app.$SID.$DOM.']" --output json \
    | jq -c '.[]' | while read -r rr; do
      aws route53 change-resource-record-sets --hosted-zone-id "$Z" --change-batch "{\"Changes\":[{\"Action\":\"DELETE\",\"ResourceRecordSet\":$rr}]}" >/dev/null \
        && echo "  레코드 삭제: app.$SID.$DOM ($(jq -r .SetIdentifier <<<"$rr"))"
    done
fi
# CLI 로 만든 것은 CallerReference(<학번>-auto-…)로, 콘솔로 만든 것(CallerReference 가 임의 값)은 검사 대상(내 ALB 주소 <학번>-cmp-alb-…)으로 찾는다
for h in $(aws route53 list-health-checks --query "HealthChecks[?starts_with(CallerReference,'$SID-auto-') || starts_with(HealthCheckConfig.FullyQualifiedDomainName || '','$SID-cmp-alb-')].Id" --output text); do
  aws route53 delete-health-check --health-check-id "$h" && echo "  헬스 체크 삭제: $h"
done
for g in "/opslab/$SID/sessions" "/opslab/$SID/runcommand"; do aws logs delete-log-group --log-group-name "$g" 2>/dev/null && echo "  로그 그룹 삭제: $g"; done
G=$(aws ssm get-document --name SSM-SessionManagerRunShell --query Content --output text 2>/dev/null | jq -r '.inputs.cloudWatchLogGroupName // ""' 2>/dev/null)
[[ "$G" == /opslab/$SID/* ]] && aws ssm delete-document --name SSM-SessionManagerRunShell && echo "  Session Manager 기본 설정 문서 삭제(기본값으로)"
N=$(aws ssm get-parameters-by-path --path /opslab/auto --query 'Parameters[].Name' --output text 2>/dev/null)
[ -n "${N// /}" ] && aws ssm delete-parameters --names $N >/dev/null && echo "  SSM /opslab/auto/* 삭제"
exit 0
