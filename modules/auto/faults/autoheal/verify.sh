#!/bin/bash
# auto autoheal 판정 — 서비스 오류 없음 + 알람→규칙→런북 연결 구성 + 연결 시험(알람을 ALARM 으로 바꾸면 런북 시작). 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start autoheal
echo "[1] 서비스"; chk_service
echo "[2] 자동 복구 연결 구성"; chk_chain
echo "[3] 연결 시험"; chk_e2e
finish
