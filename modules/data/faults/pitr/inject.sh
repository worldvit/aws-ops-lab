#!/bin/bash
# data pitr — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: orders 테이블의 일부 행 삭제(잘못된 WHERE 조건의 정리 작업)
need WRITER_EP LOADGEN
N=$(sql "SELECT count(*) FROM orders;" | tr -dc 0-9)
[ -n "$N" ] || exit 1
save rows "$N"; save deleted_at "$(date -u +%FT%TZ)"
sql "DELETE FROM orders WHERE id % 3 = 0;" | grep -q DELETE || exit 1
record 1
