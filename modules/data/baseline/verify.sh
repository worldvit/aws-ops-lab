#!/bin/bash
# data 정상 상태 정의(2단계) 판정. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../check.sh"
start baseline
echo "[1] 앱 → DB"; chk_app /db "쓰기(/db)"; chk_app "/db?ro=1" "읽기(/db?ro=1)"
echo "[2] 클러스터"; chk_cluster
[ -n "$READER_ID" ] && [ "$READER_ID" != None ] && ok "리더 인스턴스 있음($READER_ID)" || ng "리더 인스턴스 없음"
echo "[3] DB 내부"
R=$(sql "SELECT count(*) FROM pg_stat_activity WHERE state LIKE 'idle in transaction%' AND now()-xact_start > interval '60 seconds';
SELECT coalesce(max(n_dead_tup),0) FROM pg_stat_user_tables;
SELECT current_setting('default_transaction_read_only')||' '||current_setting('statement_timeout');")
mapfile -t L <<<"$R"
[ "${L[0]:-x}" = 0 ] && ok "오래된 idle in transaction 없음" || ng "60초 넘은 idle in transaction ${L[0]:-?}개"
[ "${L[1]:-999999}" -lt 50000 ] 2>/dev/null && ok "죽은 행 최대 ${L[1]}" || ng "죽은 행 최대 ${L[1]:-?} (50000 미만이어야 함)"
[ "${L[2]:-}" = "off 0" ] && ok "세션 설정 기본값(read_only off, statement_timeout 0)" || ng "세션 설정: ${L[2]:-?}"
echo "[4] 재발 방지 장치"
n=$(aws cloudwatch describe-alarms --alarm-name-prefix "$SID-data-" --query 'length(MetricAlarms)' --output text)
[ "${n:-0}" -ge 2 ] && ok "data 알람 $n 개" || ng "data 알람 ${n:-0}개 (복제 지연·연결 수 알람 2개 필요)"
finish
