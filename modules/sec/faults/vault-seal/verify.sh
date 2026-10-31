#!/bin/bash
# sec vault-seal 판정 — Vault 잠금 해제, Vault 를 쓰는 앱 기능, 보관된 키 조각. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start vault-seal
echo "[1] Vault"; chk_vault
echo "[2] 앱 기능"; chk_app /note "메모(/note) — Transit"; chk_app /db "DB 쓰기(/db) — 동적 자격증명"
echo "[3] 키 조각 보관(SSM)"
n=$(aws ssm get-parameters --names $V/unseal-1 $V/unseal-2 $V/unseal-3 --with-decryption --query 'length(Parameters[?length(Value)==`44`])' --output text)
[ "$n" = 3 ] && ok "키 조각 3개 보관(형식 정상)" || ng "형식이 맞는 키 조각 ${n:-0}/3"
finish
