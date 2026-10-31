#!/bin/bash
# iac ssm-doc 판정 — 기본 버전 내용이 원본과 같고, 실행이 모든 서버에서 성공. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start ssm-doc
echo "[1] 문서 $DOC 기본 버전"
dv=$(aws ssm describe-document --name "$DOC" --query Document.DefaultVersion --output text 2>/dev/null)
c=$(aws ssm get-document --name "$DOC" --query Content --output text 2>/dev/null | jq -c '.parameters|{s:.ServiceName.default,p:.Port.default}' 2>/dev/null)
[ "$c" = '{"s":"app","p":"8080"}' ] && ok "기본 버전 $dv: ServiceName=app, Port=8080" || ng "기본 버전 ${dv:-?}: ${c:-읽기 실패}"
echo "[2] 실행"
read -r s t <<<"$(run_doc)"; [ "$s" = "$t" ] && [ "$t" -gt 0 ] && ok "기본 버전 실행 성공 $s/$t" || ng "기본 버전 실행 성공 ${s:-0}/${t:-?}"
finish
