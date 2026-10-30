#!/bin/bash
# data vacuum-stall — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: stock 테이블(갱신 배치 stock-sync), 변형에 따라 loadgen 의 배경 작업 report-snapshot 또는 stock 의 autovacuum 설정
need WRITER_EP LOADGEN
V=$(pick_variant 2)
case $V in
  1) APW=$(pget password)
     OUT=$(bg_start report-snapshot "python3 - <<'PY'
import os, time, psycopg2
c = psycopg2.connect(host=os.environ['WRITER'], dbname='opslab', user='app', password='$APW')
cur = c.cursor()
cur.execute('BEGIN ISOLATION LEVEL REPEATABLE READ')
cur.execute('SELECT count(*) FROM orders')   # 스냅샷을 잡은 채로 트랜잭션을 끝내지 않는다
time.sleep(10**9)
PY")
     grep -q active <<<"$OUT" ;;
  2) sql "ALTER TABLE stock SET (autovacuum_enabled = false);" | grep -q ALTER ;;
esac || exit 1
OUT=$(bg_start stock-sync 'while true; do psql -h $WRITER -U opslab_admin -d opslab -qc "UPDATE stock SET qty = qty + 1 WHERE id <= 300" >/dev/null 2>&1; sleep 0.2; done')
grep -q active <<<"$OUT" || exit 1
record $V
