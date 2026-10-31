#!/bin/bash
# cicd 정상 상태 정의(2단계) 판정. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../check.sh"
start baseline
echo "[1] 파이프라인"; chk_last
echo "[2] 서비스 (릴리스 $(release))"; chk_version
echo "[3] 배포 안전장치"; chk_guard
c=$(aws codeconnections list-connections --query "Connections[?ConnectionName=='$SID-cicd-github'].ConnectionStatus | [0]" --output text 2>/dev/null)
[ "$c" = AVAILABLE ] && ok "소스 연결 $SID-cicd-github AVAILABLE" || ng "소스 연결 $SID-cicd-github ${c:-없음}"
finish
