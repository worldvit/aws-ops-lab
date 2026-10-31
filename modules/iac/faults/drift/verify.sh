#!/bin/bash
# iac drift 판정 — 드리프트 없음, /promo. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start drift
echo "[1] 드리프트"; chk_drift
echo "[2] 서비스"; chk_promo
finish
