#!/bin/bash
# data vacuum-stall — rollback
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
need WRITER_EP LOADGEN
bg_stop stock-sync report-snapshot && echo "  배경 작업 stock-sync·report-snapshot 중지"
sql "ALTER TABLE stock RESET (autovacuum_enabled);
SELECT count(pg_terminate_backend(pid)) FROM pg_stat_activity WHERE state LIKE 'idle in transaction%' AND now()-xact_start > interval '30 seconds';
VACUUM stock;
SELECT 'stock 죽은 행 '||n_dead_tup FROM pg_stat_user_tables WHERE relname='stock';" | sed 's/^/  /'
