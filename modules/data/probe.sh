#!/bin/bash
# DB 점검 도구 — 앱에서 본 DB 상태와 DB 안의 상태를 한 화면에 본다. 실행 위치: CloudShell (약 30초)
#   bash ~/opslab/modules/data/probe.sh
DATA_NO_LAB=1 source "$(dirname "$(readlink -f "$0")")/lib.sh"
DNS=$(alb_dns)
echo "== $(date '+%F %T') DB 점검: $SID ($CLUSTER, 상태 ${DB_STATUS:-없음}) =="
try() {  # $1=경로 → "성공수/5 마지막오류"
  local ok=0 err="" i body
  for i in 1 2 3 4 5; do
    body=$(curl -s -m 6 "http://$DNS$1"); grep -q '"status":"ok"' <<<"$body" && ok=$((ok+1)) || err=$(jq -r '.message // empty' <<<"$body" 2>/dev/null)
  done; echo "$ok/5 ${err:0:110}"
}
w=$(try /db); r=$(try "/db?ro=1")
m() { case "$1" in 5/5*) echo "✅";; 0/5*) echo "❌";; *) echo "⚠️ ";; esac; }
printf '%s ① 앱 → DB 쓰기 (/db)          %s\n' "$(m "$w")" "$w"
printf '%s ② 앱 → DB 읽기 (/db?ro=1, 리더) %s\n' "$(m "$r")" "$r"
echo "③ 클러스터: 라이터=${WRITER_ID:-?} 리더=${READER_ID:-?}  앱 설정 host=$(pget host | cut -d. -f1)"
if [ -n "$WRITER_EP" ] && [ "$WRITER_EP" != None ]; then
  sql "SELECT '④ 연결: '||count(*)||' / max_connections '||current_setting('max_connections') FROM pg_stat_activity;
SELECT '⑤ idle in transaction 최장: '||coalesce(max(extract(epoch FROM now()-xact_start))::int||'초','없음') FROM pg_stat_activity WHERE state LIKE 'idle in transaction%';
SELECT '⑥ 죽은 행 많은 테이블: '||coalesce(string_agg(relname||'='||n_dead_tup, ', '),'없음') FROM (SELECT relname, n_dead_tup FROM pg_stat_user_tables ORDER BY n_dead_tup DESC LIMIT 3) t;
SELECT '⑦ 세션 설정: read_only='||current_setting('default_transaction_read_only')||' statement_timeout='||current_setting('statement_timeout');" | sed 's/^/  /'
fi
LAG=$(aws cloudwatch get-metric-statistics --namespace AWS/RDS --metric-name AuroraReplicaLagMaximum --dimensions Name=DBClusterIdentifier,Value="$CLUSTER" \
  --start-time "$(date -u -d '-3 min' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" --period 60 --statistics Maximum --query 'max(Datapoints[].Maximum)' --output text 2>/dev/null)
echo "  ⑧ 복제 지연(최근 3분 최대): ${LAG:-None} ms"
echo "(✅ 정상  ⚠️ 일부 실패  ❌ 전부 실패)"
