#!/bin/bash
# rel az 판정 — /api·/db 정상(AZ 장애가 계속되는 중이어도), ASG·DB 가 두 AZ 에 걸침. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start az
echo "[1] 서비스"; chk_service
echo "[2] AZ 구성"; chk_az
[ -n "$(fis_running)" ] && echo "  (참고) AZ-a 단절 실험 진행 중: $(fis_running) — 끝날 때까지 기다리지 말고 지금 상태로 복구합니다"
finish
