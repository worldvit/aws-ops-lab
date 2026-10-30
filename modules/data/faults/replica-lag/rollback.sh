#!/bin/bash
# data replica-lag — rollback
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
need WRITER_EP LOADGEN
bg_stop order-import report-analytics && echo "  배경 작업 order-import·report-analytics 중지"
sql "SELECT count(pg_terminate_backend(pid)) FROM pg_stat_activity WHERE query LIKE '%bulk%' AND pid <> pg_backend_pid(); TRUNCATE bulk;" 2>/dev/null | sed 's/^/  /'
