#!/bin/bash
# L3 층 초기화 — 앱 계정(app)과 테이블(hits·orders·stock)을 만든다. 여러 번 실행해도 안전하다.
# common/start.sh 가 L3 층 배포 뒤 자동으로 부른다. 수강생은 data 모듈 1단계에서 직접 실행한다.
#   bash ~/opslab/layers/l3-data.init.sh
DATA_NO_LAB=1 source "$(dirname "$(readlink -f "$0")")/../modules/data/lib.sh"
need WRITER_EP ADMIN_PW LOADGEN
APP_PW=$(pget password)
[ -n "$APP_PW" ] && [ "$APP_PW" != None ] || { echo "SSM $P/password 가 없습니다"; exit 1; }
echo "== DB 초기화: $WRITER_EP"
sql "DO \$\$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='app') THEN CREATE ROLE app LOGIN PASSWORD '$APP_PW';
  ELSE ALTER ROLE app LOGIN PASSWORD '$APP_PW'; END IF; END \$\$;
GRANT ALL ON DATABASE opslab TO app;
GRANT ALL ON SCHEMA public TO app;
CREATE TABLE IF NOT EXISTS hits (id bigserial PRIMARY KEY, at timestamptz DEFAULT now(), host text);
CREATE TABLE IF NOT EXISTS orders (id serial PRIMARY KEY, item text, qty int, created timestamptz DEFAULT now());
CREATE TABLE IF NOT EXISTS stock (id int PRIMARY KEY, qty int, note text);
INSERT INTO orders(item, qty) SELECT 'item-'||g, (g % 9) + 1 FROM generate_series(1,1000) g WHERE NOT EXISTS (SELECT 1 FROM orders);
INSERT INTO stock SELECT g, 100, repeat('s', 200) FROM generate_series(1,1000) g ON CONFLICT DO NOTHING;
ALTER TABLE hits OWNER TO app; ALTER TABLE orders OWNER TO app; ALTER TABLE stock OWNER TO app;
SELECT 'orders=' || count(*) FROM orders;"
