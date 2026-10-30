#!/bin/bash
# data conn-limit — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: loadgen 의 배경 작업(db-report) 또는 DB 역할·데이터베이스의 연결 한도
need WRITER_EP LOADGEN
V=$(pick_variant 3)
case $V in
  1) APW=$(pget password)
     OUT=$(bg_start db-report "python3 - <<'PY'
import os, time, psycopg2
held = []
while True:   # 연결을 열어 두기만 하고 닫지 않는다(연결 누수)
    try:
        held.append(psycopg2.connect(host=os.environ['WRITER'], dbname='opslab', user='app', password='$APW', connect_timeout=3))
    except Exception:
        time.sleep(1)
PY")
     grep -q active <<<"$OUT" ;;
  2) sql "ALTER ROLE app CONNECTION LIMIT 0;" postgres | grep -q ALTER ;;
  3) sql "ALTER DATABASE opslab CONNECTION LIMIT 0;" postgres | grep -q ALTER ;;
esac || exit 1
record $V
