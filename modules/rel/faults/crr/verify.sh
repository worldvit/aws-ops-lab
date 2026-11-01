#!/bin/bash
# rel crr 판정 — 두 버킷 버전 관리, 복제 규칙(전체), 새 파일이 3분 안에 도쿄에 도착. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start crr
echo "[1] 교차 리전 복제"; chk_crr
finish
