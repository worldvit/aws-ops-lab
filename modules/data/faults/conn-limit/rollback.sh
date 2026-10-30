#!/bin/bash
# data conn-limit — rollback
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
need WRITER_EP LOADGEN
bg_stop db-report && echo "  배경 작업 db-report 중지"
sql "ALTER ROLE app CONNECTION LIMIT -1; ALTER DATABASE opslab CONNECTION LIMIT -1;
SELECT count(pg_terminate_backend(pid)) FROM pg_stat_activity WHERE usename='app' AND state='idle' AND now()-state_change > interval '20 seconds';" postgres | sed 's/^/  /'
