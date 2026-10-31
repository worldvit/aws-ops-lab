#!/bin/bash
# sec transit-rotate 판정 — 메모 암호화·복호화, 키 설정, 앱 정책. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start transit-rotate
echo "[1] 앱 기능"; chk_app /note "메모(/note) — 새 메모 암호화 + 가장 오래된 메모 복호화"
echo "[2] Transit 키 orders"
read -r mn lt <<<"$(vrun "vault read -format=json transit/keys/orders | jq -r '.data|\"\(.min_decryption_version) \(.latest_version)\"'" 30)"
[ "$mn" = 1 ] && ok "최소 복호화 버전 1 (현재 버전 $lt)" || ng "최소 복호화 버전 ${mn:-?} (현재 버전 ${lt:-?}) — 옛 데이터는 1부터 풀 수 있어야 함"
chk_vpolicy
finish
