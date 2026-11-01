#!/bin/bash
# auto autoheal — rollback. 연결(규칙·역할 정책·알람)을 원본으로, 오류율 0으로 되돌린다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
aws events enable-rule --name "$RULE" && echo "  규칙 $RULE ENABLED"
put_events_policy && echo "  EventBridge 역할 정책 원본"
put_alarm 10 && echo "  알람 임계값 10"
set_error_rate 0 && echo "  앱 서버 오류율 0"
aws cloudwatch set-alarm-state --alarm-name "$ALARM" --state-value OK --state-reason "opslab rollback" 2>/dev/null
exit 0
