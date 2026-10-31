#!/bin/bash
# iac 정상 상태 정의(2단계) 판정. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../check.sh"
start baseline
echo "[1] 스택"; chk_stack; chk_drift
echo "[2] 서비스"; chk_promo
B=$(soutput ArtifactBucket)
aws s3api head-object --bucket "$B" --key release/app.txt >/dev/null 2>&1 && ok "산출물 s3://$B/release/app.txt 있음" || ng "산출물 s3://${B:-?}/release/app.txt 없음"
echo "[3] 운영 자동화(SSM 문서)"
read -r s t <<<"$(run_doc)"; [ "$s" = "$t" ] && [ "$t" -gt 0 ] && ok "문서 $DOC 기본 버전 실행 성공 $s/$t" || ng "문서 $DOC 기본 버전 실행 성공 ${s:-0}/${t:-?}"
echo "[4] 패치"
n=$(aws ssm describe-instance-patch-states --instance-ids $(app_ids) --query 'length(InstancePatchStates)' --output text 2>/dev/null)
[ "${n:-0}" -ge 1 ] && ok "패치 상태 보고 앱 서버 ${n}대" || ng "패치 스캔 기록 없음(1-7 Patch Manager 스캔)"
finish
