#!/bin/bash
# data replica-lag — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: loadgen 의 배경 작업(order-import: 라이터 대량 쓰기, 변형 2는 report-analytics: 리더 무거운 조회 추가)과 bulk 테이블
need WRITER_EP READER_EP LOADGEN
V=$(pick_variant 2)
sql "CREATE TABLE IF NOT EXISTS bulk (id bigserial PRIMARY KEY, payload text); ALTER TABLE bulk OWNER TO app;" >/dev/null
OUT=$(bg_start order-import 'for w in 1 2 3 4 5 6; do (while true; do psql -h $WRITER -U opslab_admin -d opslab -qc "INSERT INTO bulk(payload) SELECT md5(g::text)||repeat(chr(65+(g%26)),1500) FROM generate_series(1,20000) g" >/dev/null 2>&1; done) & done; wait')
grep -q active <<<"$OUT" || exit 1
if [ "$V" = 2 ]; then
  OUT=$(bg_start report-analytics 'for w in 1 2 3 4; do (while true; do psql -h $READER -U opslab_admin -d opslab -qc "SELECT count(*), sum(length(payload)) FROM bulk b1 JOIN bulk b2 USING (id)" >/dev/null 2>&1; done) & done; wait')
  grep -q active <<<"$OUT" || exit 1
fi
record $V
