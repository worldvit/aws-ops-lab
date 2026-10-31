#!/bin/bash
# iac rollback-stuck 판정 — 스택이 롤백·실패 상태가 아니고, 사전 점검 의존 설정이 정상. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start rollback-stuck
echo "[1] 스택"
s=$(stack_status); case "$s" in *FAILED|*IN_PROGRESS) ng "스택 $STACK $s";; *) ok "스택 $STACK $s (롤백 교착 해소)";; esac
chk_promo
echo "[2] 외부 의존 설정"
d=$(aws ssm get-parameter --name /opslab/iac/dependency --query Parameter.Value --output text 2>/dev/null)
[ "$d" = ready ] && ok "/opslab/iac/dependency=ready" || ng "/opslab/iac/dependency=${d:-없음}"
a=$(aws s3 cp "s3://$(soutput ArtifactBucket)/config/allowed.json" - 2>/dev/null | jq -c .allowed 2>/dev/null)
grep -q '"v1"' <<<"$a" && ok "config/allowed.json $a" || ng "config/allowed.json ${a:-없음} (현재 릴리스 v1 을 허용해야 함)"
finish
