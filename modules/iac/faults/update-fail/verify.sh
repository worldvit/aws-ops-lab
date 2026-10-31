#!/bin/bash
# iac update-fail 판정 — 릴리스 v2 가 완료됐는가. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start update-fail
echo "[1] 스택"; chk_stack
r=$(sparam PromoText); [ "$r" = v2 ] && ok "릴리스 매개변수 PromoText=v2" || ng "릴리스 매개변수 PromoText=${r:-?} (v2 배포를 완료해야 함)"
echo "[2] 서비스"; chk_promo
finish
