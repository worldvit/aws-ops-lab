#!/bin/bash
# data conn-limit 판정 — 앱 쓰기, 연결 한도, 연결 수. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start conn-limit
echo "[1] 앱 → DB"; chk_app /db "쓰기(/db)"
echo "[2] 연결 한도와 연결 수"
mapfile -t L <<<"$(sql "SELECT rolconnlimit FROM pg_roles WHERE rolname='app';
SELECT datconnlimit FROM pg_database WHERE datname='opslab';
SELECT count(*)||' '||current_setting('max_connections') FROM pg_stat_activity;" postgres)"
[ "${L[0]:-x}" = -1 ] && ok "역할 app 연결 한도 없음(-1)" || ng "역할 app 연결 한도 ${L[0]:-?}"
[ "${L[1]:-x}" = -1 ] && ok "데이터베이스 opslab 연결 한도 없음(-1)" || ng "데이터베이스 opslab 연결 한도 ${L[1]:-?}"
read -r C M <<<"${L[2]:-0 1}"
[ "$C" -lt $((M / 2)) ] 2>/dev/null && ok "연결 수 $C / $M" || ng "연결 수 $C / $M (절반 미만이어야 함)"
chk_jobs db-report
finish
