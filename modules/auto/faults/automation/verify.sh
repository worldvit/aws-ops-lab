#!/bin/bash
# auto automation 판정 — 런북 기본 버전의 대상 태그가 맞고, 안전 스위치 on, 실행 Success. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start automation
echo "[1] 런북 문서"
dv=$(aws ssm describe-document --name "$RUNBOOK" --query Document.DefaultVersion --output text 2>/dev/null)
t=$(aws ssm get-document --name "$RUNBOOK" --document-format JSON --query Content --output text 2>/dev/null | jq -r '.parameters.TagValue.default')
[ "$t" = "$APP_TAG" ] && ok "기본 버전 $dv: 대상 태그 $t" || ng "기본 버전 ${dv:-?}: 대상 태그 '$t' (기대 $APP_TAG)"
echo "[2] 실행"; chk_runbook
finish
