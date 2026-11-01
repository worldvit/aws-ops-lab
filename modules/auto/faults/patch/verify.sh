#!/bin/bash
# auto patch 판정 — 유지관리 기간 켜짐, 대상 태그가 실행 중인 앱 서버와 맞음, 패치 작업 등록. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start patch
echo "[1] 유지관리 기간"; chk_mw
finish
