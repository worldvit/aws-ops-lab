#!/bin/bash
# auto autoheal — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: 자동 복구 연결(규칙 상태 / EventBridge 역할 정책 / 알람 임계값) 중 하나를 바꾼 뒤,
#           모든 앱 서버의 /api 오류율을 30%로 올린다(설정 파일 한 줄 + 앱 재시작). /health 는 정상이라 서버 교체는 일어나지 않는다.
aws events describe-rule --name "$RULE" >/dev/null 2>&1 || exit 3
V_=$(pick_variant 3)
case $V_ in
  1) # 작업 중 오작동이 걱정돼 규칙을 잠시 꺼 두고 잊음
     aws events disable-rule --name "$RULE" || exit 1 ;;
  2) # 권한 정리 중 EventBridge 역할의 런북 시작 권한이 지워짐
     aws iam delete-role-policy --role-name "$SID-auto-events-role" --policy-name start-automation || exit 1 ;;
  3) # 알람이 너무 자주 울린다며 임계값을 크게 올림(1분 5xx 10건 → 1000건)
     put_alarm 1000 || exit 1 ;;
esac
set_error_rate 0.3 || exit 1
record $V_
