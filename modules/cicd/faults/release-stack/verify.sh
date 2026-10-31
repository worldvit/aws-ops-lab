#!/bin/bash
# cicd release-stack 판정 — 릴리스 스택이 안정 상태, 기록된 릴리스 = 서비스 버전, 마지막 실행 성공. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start release-stack
echo "[1] 릴리스 스택"
s=$(aws cloudformation describe-stacks --stack-name "$RSTACK" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo NONE)
case "$s" in CREATE_COMPLETE|UPDATE_COMPLETE) ok "스택 $RSTACK $s";; *) ng "스택 $RSTACK $s";; esac
n=$(aws iam list-role-policies --role-name "$SID-cicd-cfn-role" --query "length(PolicyNames[?@=='opslab-fault-deny'])" --output text)
[ "$n" = 0 ] && ok "변경셋 실행 역할에 거부 정책 없음" || ng "변경셋 실행 역할에 거부 정책 있음"
echo "[2] 파이프라인"; chk_last
echo "[3] 서비스"; chk_version
finish
