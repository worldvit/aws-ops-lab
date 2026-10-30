#!/bin/bash
# data pitr 판정 — orders 행 수가 장애 전과 같은지. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start pitr
echo "[1] 앱 → DB"; chk_app /db "쓰기(/db)"
echo "[2] 주문 데이터"
EXP=$(aws ssm get-parameter --name /opslab/injections/data-6/rows --query Parameter.Value --output text 2>/dev/null); EXP=${EXP:-1000}
N=$(sql "SELECT count(*) FROM orders;" | tr -dc 0-9)
[ "$N" = "$EXP" ] && ok "orders $N 행 (장애 전 $EXP 행)" || ng "orders ${N:-?} 행 (장애 전 $EXP 행이어야 함)"
M=$(sql "SELECT count(*) FROM generate_series(1,1000) g WHERE g % 3 = 0 AND NOT EXISTS (SELECT 1 FROM orders o WHERE o.id = g);" | tr -dc 0-9)
[ "${M:-1}" = 0 ] && ok "사라졌던 주문 번호가 모두 돌아옴" || ng "아직 없는 주문 번호 ${M:-?}개"
R=$(aws rds describe-db-clusters --query "DBClusters[?starts_with(DBClusterIdentifier,'$SID-data-restore')].DBClusterIdentifier" --output text)
[ -z "$R" ] && ok "복원용 클러스터 정리됨" || echo "  [참고] 복원용 클러스터가 남아 있습니다: $R (복구가 끝났으면 지우세요 — 시간당 과금)"
finish
