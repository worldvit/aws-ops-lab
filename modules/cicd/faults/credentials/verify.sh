#!/bin/bash
# cicd credentials 판정 — 파이프라인 역할에 거부 정책 없음, 연결 사용 가능, 마지막 실행 성공. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start credentials
echo "[1] 자격증명"
n=$(aws iam list-role-policies --role-name "$SID-cicd-pipeline-role" --query "length(PolicyNames[?@=='opslab-fault-deny'])" --output text)
[ "$n" = 0 ] && ok "파이프라인 역할에 거부 정책 없음" || ng "파이프라인 역할에 거부 정책(opslab-fault-deny) 있음"
c=$(aws codeconnections list-connections --query "Connections[?ConnectionName=='$SID-cicd-github'].ConnectionStatus | [0]" --output text)
[ "$c" = AVAILABLE ] && ok "소스 연결 AVAILABLE" || ng "소스 연결 $c"
echo "[2] 파이프라인"; chk_last
echo "[3] 서비스"; chk_version
finish
