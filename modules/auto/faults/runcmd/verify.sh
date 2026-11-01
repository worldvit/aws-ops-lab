#!/bin/bash
# auto runcmd 판정 — 모든 앱 서버 SSM Online, 태그 대상 Run Command 가 ASG 전체에서 성공. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start runcmd
echo "[1] SSM 연결"; chk_online
echo "[2] 동시 조치"; chk_runcmd
finish
