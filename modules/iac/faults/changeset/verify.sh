#!/bin/bash
# iac changeset 판정 — 현재 스택 버킷에 산출물이 있는가, 스택 안정. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start changeset
echo "[1] 스택"; chk_stack
echo "[2] 산출물"
B=$(soutput ArtifactBucket)
for k in release/app.txt config/allowed.json; do
  aws s3api head-object --bucket "$B" --key "$k" >/dev/null 2>&1 && ok "s3://$B/$k 있음" || ng "s3://${B:-?}/$k 없음"
done
finish
