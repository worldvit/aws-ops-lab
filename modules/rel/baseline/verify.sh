#!/bin/bash
# rel 정상 상태 정의(2단계) 판정. 실행 위치: CloudShell (1~3분)
source "$(dirname "$(readlink -f "$0")")/../check.sh"
start baseline
echo "[1] 서비스"; chk_service
echo "[2] 백업과 RPO"; chk_backup
echo "[3] 교차 리전 복제"; chk_crr
echo "[4] AZ 복원력"; chk_az; chk_drill
[ -z "$(fis_running)" ] && ok "진행 중인 FIS 실험 없음" || ng "진행 중인 FIS 실험: $(fis_running)"
echo "[5] 비용(과대·유휴)"; chk_cost
finish
