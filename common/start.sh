#!/bin/bash
# 모듈 시작 — 모듈에 필요한 환경 층을 아래(L1)부터 차례로 배포한다. CloudShell에서 실행.
#   bash ~/opslab/common/start.sh cmp         # cmp 모듈 시작: requires 층까지 (cmp → L1)
#   bash ~/opslab/common/start.sh cmp full    # 따라잡기: builds 층까지 (cmp → L1, L2 = cmp 완료 상태)
# L0 층(<학번>-l0)은 Day 0에 한 번만 배포하며 이 스크립트는 건드리지 않는다.
# 배포가 끝나면 층의 출력값(ALB 주소 등)을 ~/opslab-env.sh 에 추가한다.
set -uo pipefail
: "${SID:?SID 환경변수에 학번을 넣으세요. 예) source ~/opslab-env.sh}"
export AWS_REGION="${AWS_REGION:-ap-northeast-2}"
ROOT=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
MOD=${1:?모듈 ID를 적으세요. 예) start.sh cmp}; MY="$ROOT/modules/$MOD/module.yaml"
[ -f "$MY" ] || { echo "❌ 모듈이 없습니다: $MOD"; exit 1; }
KEY=requires; [ "${2:-}" = full ] && KEY=builds
TOP=$(sed -n "s/^$KEY: *L\([0-9]\).*/\1/p" "$MY"); TOP=${TOP:-0}

aws cloudformation describe-stacks --stack-name "$SID-l0" >/dev/null 2>&1 \
  || { echo "❌ L0 층($SID-l0)이 없습니다. Day 0 준비를 먼저 끝내세요."; exit 1; }

declare -A FILE=([1]=l1-network [2]=l2-app [3]=l3-data [4]=l4-secret)
declare -A OWNER=([1]=base [2]=cmp [3]=data [4]=sec)
for n in $(seq 1 "$TOP"); do
  st="$SID-l$n"; tpl="$ROOT/layers/${FILE[$n]}.yaml"
  [ -f "$tpl" ] || { echo "❌ 층 템플릿이 아직 없습니다: layers/${FILE[$n]}.yaml"; exit 1; }
  echo "== L$n 층 배포: $st (${FILE[$n]}) — 수 분 걸립니다"
  aws cloudformation deploy --stack-name "$st" --template-file "$tpl" --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides StudentId="$SID" --tags Course=opslab Module="${OWNER[$n]}" Owner="$SID" --no-fail-on-empty-changeset \
    | tail -1 || { echo "❌ $st 배포 실패 — 콘솔 CloudFormation 이벤트를 확인하세요."; exit 1; }
  # 출력값을 환경 파일에 (예: AlbDns → ALB_DNS)
  aws cloudformation describe-stacks --stack-name "$st" --query 'Stacks[0].Outputs[].[OutputKey,OutputValue]' --output text \
    | while read -r k v; do
        var=$(sed -E 's/([a-z0-9])([A-Z])/\1_\2/g' <<<"$k" | tr a-z A-Z)
        echo "export $var=$v" >> ~/opslab-env.sh
      done
done
echo "✅ $MOD 시작 준비 완료 (L1~L$TOP). 'source ~/opslab-env.sh' 로 변수를 불러오세요."
