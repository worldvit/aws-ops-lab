#!/bin/bash
# 모듈 시작 — 모듈에 필요한 환경 층을 아래(L1)부터 차례로 배포한다. CloudShell에서 실행.
#   bash ~/opslab/common/start.sh cmp         # cmp 모듈 시작: requires 층까지 (cmp → L1)
#   bash ~/opslab/common/start.sh cmp full    # 따라잡기: builds 층까지 (cmp → L1, L2 = cmp 완료 상태)
# 모듈에 env.yaml(주변 구성)이 있으면 층 다음에 <학번>-<모듈>-env 로, full 이고 done.yaml(완료 상태)이 있으면 <학번>-<모듈>-done 으로 배포한다.
# L0 층(<학번>-l0)은 Day 0에 한 번만 배포하며 이 스크립트는 건드리지 않는다.
# 배포가 끝나면 층의 출력값(ALB 주소 등)을 ~/opslab-env.sh 에 추가한다.
set -uo pipefail
: "${SID:?SID 환경변수에 학번을 넣으세요. 예) source ~/opslab-env.sh}"
export AWS_REGION="${AWS_REGION:-ap-northeast-2}"
ROOT=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
MOD=${1:?모듈 ID를 적으세요. 예) start.sh cmp}; MY="$ROOT/modules/$MOD/module.yaml"
[ -f "$MY" ] || { echo "❌ 모듈이 없습니다: $MOD"; exit 1; }
KEY=requires; [ "${2:-}" = full ] && KEY=builds
lv() { sed -n "s/^$1: *L\([0-9]\).*/\1/p" "$MY"; }
TOP=$(lv requires); TOP=${TOP:-0}
B=$(lv builds); [ "$KEY" = builds ] && [ "${B:-0}" -gt "$TOP" ] && TOP=$B   # builds 가 층이 아니면(—) requires 까지

aws cloudformation describe-stacks --stack-name "$SID-l0" >/dev/null 2>&1 \
  || { echo "❌ L0 층($SID-l0)이 없습니다. Day 0 준비를 먼저 끝내세요."; exit 1; }

declare -A FILE=([1]=l1-network [2]=l2-app [3]=l3-data [4]=l4-secret)
declare -A OWNER=([1]=base [2]=cmp [3]=data [4]=sec)
deploy() {  # $1=스택 이름 $2=템플릿 $3=Module 태그 — 배포 후 출력값을 환경 파일에 추가(예: AlbDns → ALB_DNS)
  echo "== 배포: $1 ($(basename "$2")) — 수 분 걸립니다"
  aws cloudformation deploy --stack-name "$1" --template-file "$2" --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides StudentId="$SID" --tags Course=opslab Module="$3" Owner="$SID" --no-fail-on-empty-changeset \
    | tail -1
  [ "${PIPESTATUS[0]}" -eq 0 ] || { echo "❌ $1 배포 실패 — 콘솔 CloudFormation 이벤트를 확인하세요."; exit 1; }
  aws cloudformation describe-stacks --stack-name "$1" --query 'Stacks[0].Outputs[].[OutputKey,OutputValue]' --output text \
    | while read -r k v; do
        var=$(sed -E 's/([a-z0-9])([A-Z])/\1_\2/g' <<<"$k" | tr a-z A-Z)
        echo "export $var=$v" >> ~/opslab-env.sh
      done
}
for n in $(seq 1 "$TOP"); do
  tpl="$ROOT/layers/${FILE[$n]}.yaml"
  [ -f "$tpl" ] || { echo "❌ 층 템플릿이 아직 없습니다: layers/${FILE[$n]}.yaml"; exit 1; }
  deploy "$SID-l$n" "$tpl" "${OWNER[$n]}"
  init="$ROOT/layers/${FILE[$n]}.init.sh"; [ -f "$init" ] && { source ~/opslab-env.sh; bash "$init" || exit 1; }   # 층 초기화(예: DB 계정·테이블)
done
# 모듈 주변 구성(env.yaml)과, 따라잡기일 때 모듈 완료 상태(done.yaml)
[ -f "$ROOT/modules/$MOD/env.yaml" ] && deploy "$SID-$MOD-env" "$ROOT/modules/$MOD/env.yaml" "$MOD"
[ "$KEY" = builds ] && [ -f "$ROOT/modules/$MOD/done.yaml" ] && deploy "$SID-$MOD-done" "$ROOT/modules/$MOD/done.yaml" "$MOD"
# 따라잡기: 완료 상태를 템플릿 하나로 만들 수 없는 모듈은 full.sh(따라하기 명령 모음)를 실행한다
[ "$KEY" = builds ] && [ -f "$ROOT/modules/$MOD/full.sh" ] && { source ~/opslab-env.sh; bash "$ROOT/modules/$MOD/full.sh" || exit 1; }
echo "✅ $MOD 시작 준비 완료. 'source ~/opslab-env.sh' 로 변수를 불러오세요."
