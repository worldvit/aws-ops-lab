#!/bin/bash
# auto session 판정 — 모든 앱 서버 SSM Online, 세션 접속, 접속 기록 남음. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start session
echo "[1] SSM 연결"; chk_online
echo "[2] 세션 접속과 기록"; chk_session
finish
