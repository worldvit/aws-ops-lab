#!/bin/bash
# data vacuum-stall 판정 — 오래 열린 트랜잭션, autovacuum 설정, 죽은 행 수. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start vacuum-stall
echo "[1] 앱 → DB"; chk_app /db "쓰기(/db)"
echo "[2] DB 내부"
mapfile -t L <<<"$(sql "SELECT count(*) FROM pg_stat_activity WHERE state LIKE 'idle in transaction%' AND now()-xact_start > interval '60 seconds';
SELECT coalesce(array_to_string(reloptions, ','), '') FROM pg_class WHERE relname='stock';
SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname='stock';
SELECT pg_size_pretty(pg_total_relation_size('stock'));")"
[ "${L[0]:-x}" = 0 ] && ok "60초 넘은 idle in transaction 없음" || ng "60초 넘은 idle in transaction ${L[0]:-?}개"
grep -q 'autovacuum_enabled=false' <<<"${L[1]:-}" && ng "stock 의 autovacuum 이 꺼져 있음 (${L[1]})" || ok "stock autovacuum 켜짐"
[ "${L[2]:-999999}" -lt 20000 ] 2>/dev/null && ok "stock 죽은 행 ${L[2]} (크기 ${L[3]:-?})" || ng "stock 죽은 행 ${L[2]:-?} (20000 미만이어야 함, 크기 ${L[3]:-?})"
finish
