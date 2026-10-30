#!/bin/bash
# 장애 주입 도구 (수강생용) — CloudShell에서 내 권한으로 실행한다.
#   bash ~/opslab/common/inject.sh 1-1            Lab 1-1 장애 주입 (가설 수립을 끝낸 뒤)
#   bash ~/opslab/common/inject.sh done 1-1       해결 기록 (verify.sh 통과 후)
#   bash ~/opslab/common/inject.sh rollback 1-1   원복 (주입 후 40분 안에 해결하지 못했을 때)
#   bash ~/opslab/common/inject.sh status         내 Lab별 주입·해결·원복 기록 보기
#
# 장애 내용은 dayN/<장애명>/inject.sh 에 공개되어 있다. 무작위 변형 하나를 주입하고,
# 기록(시각·변형·원복 정보)은 내 계정 SSM Parameter Store /opslab/injections/<Lab> 에 남긴다.
set -uo pipefail
: "${SID:?SID 환경변수에 학번을 넣으세요. 예) source ~/opslab-env.sh}"
export AWS_REGION="${AWS_REGION:-ap-northeast-2}" SID
ROOT=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
P=/opslab/injections
now() { TZ=Asia/Seoul date '+%Y-%m-%dT%H:%M:%S%z'; }
usage() { sed -n '3,6p' "$0" | sed 's/^#//'; exit 1; }

case "${1:-}" in
  [0-9]-[0-9]) ACTION=inject; LAB=$1 ;;
  done|rollback) ACTION=$1; LAB=${2:-}; [ -z "$LAB" ] && usage ;;
  status) ACTION=status; LAB="" ;;
  *) usage ;;
esac

if [ "$ACTION" = status ]; then
  echo "✅ $SID 주입 기록"
  aws ssm get-parameters-by-path --path "$P" --query 'Parameters[].Value' --output json 2>/dev/null \
    | jq -r '.[] | fromjson? | objects | select(.lab) | "  Lab \(.lab)  \(.state|.+"           "|.[0:11]) 주입 \(.injected_at // "-")  해결 \(.resolved_at // "-")  원복 \(.rolled_back_at // "-")"' | sort
  exit 0
fi

ROW=$(grep "^$LAB," "$ROOT/common/labs.csv") || { echo "❌ Lab 번호는 $(tail -n +2 "$ROOT/common/labs.csv" | cut -d, -f1 | paste -sd' ') 중 하나입니다"; exit 1; }
DIR=$(cut -d, -f2 <<<"$ROW"); TYPE=$(cut -d, -f3- <<<"$ROW")
META=$(aws ssm get-parameter --name "$P/$LAB" --query Parameter.Value --output text 2>/dev/null) || META='{}'
STATE=$(jq -r '.state // empty' <<<"$META")
put_meta() { aws ssm put-parameter --name "$P/$LAB" --type String --overwrite --value "$1" >/dev/null; }
export LAB

case $ACTION in
inject)
  [ "$STATE" = injected ] && { echo "❌ Lab $LAB 장애가 이미 주입되어 있습니다. 다시 하려면 rollback 을 먼저 실행하세요."; exit 1; }
  # 지난 시도의 원복 정보는 지운다
  OLD=$(aws ssm get-parameters-by-path --path "$P/$LAB" --query 'Parameters[].Name' --output text 2>/dev/null)
  [ -n "$OLD" ] && aws ssm delete-parameters --names $OLD >/dev/null
  bash "$ROOT/$DIR/inject.sh" >/dev/null || {
    echo "❌ 주입 실패 — 위 오류를 확인하세요. 일부 바뀐 설정을 되돌립니다."
    bash "$ROOT/$DIR/rollback.sh" >/dev/null 2>&1; exit 1; }
  T=$(now); ATT=$(( $(jq -r '.attempt // 0' <<<"$META") + 1 ))
  put_meta "$(jq -nc --arg l "$LAB" --arg d "$DIR" --arg t "$T" --argjson a "$ATT" \
    '{lab:$l, fault:$d, state:"injected", injected_at:$t, attempt:$a}')"
  echo "✅ 장애를 주입했습니다. 주입 시각을 기록표의 기준으로 적고 5단계 관찰을 시작하세요."
  echo "   장애 유형: $TYPE"
  echo "   주입 시각: $T" ;;
done)
  [ "$STATE" = injected ] || { echo "❌ Lab $LAB 에 진행 중인 주입 기록이 없습니다."; exit 1; }
  put_meta "$(jq -c --arg t "$(now)" '.state="resolved" | .resolved_at=$t' <<<"$META")"
  echo "✅ 해결 기록을 남겼습니다. 정답 요약 토글로 원인을 대조하고 런북을 작성하세요." ;;
rollback)
  [ "$STATE" = injected ] || { echo "❌ Lab $LAB 에 원복할 주입 기록이 없습니다."; exit 1; }
  read -r -p "원복하면 이 Lab의 진단 기회가 끝납니다. 계속할까요? (y/N) " a; [ "$a" = y ] || exit 1
  bash "$ROOT/$DIR/rollback.sh" || { echo "❌ 원복 중 오류 — 따라잡기 템플릿(catchup/)으로 다시 만드세요."; exit 1; }
  put_meta "$(jq -c --arg t "$(now)" '.state="rolled_back" | .rolled_back_at=$t' <<<"$META")"
  echo "✅ 원복했습니다. 3~5분 뒤 verify.sh 로 정상 상태를 확인하고, 정답 요약 토글로 원인을 대조한 뒤 런북을 작성하세요." ;;
esac
