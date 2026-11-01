#!/bin/bash
# rel backup 판정 — 보존 7일 이상, 삭제 방지, 복원 가능한 최근 시각 10분 이내. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start backup
echo "[1] 백업 설정과 RPO"; chk_backup
finish
