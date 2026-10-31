#!/bin/bash
# 이어 하기 가능한 모듈 시험 — CloudShell 이 중간에 다시 시작돼도 끝난 변형은 건너뛰고 다음부터 이어 간다.
#   SID=s00 bash ~/opslab/tools/test-resume.sh cicd "cicd-1:2 cicd-1:3 cicd-2:1 …"   (Lab:변형 목록, 생략하면 모듈 전체)
#   진행 기록: ~/resume-<모듈>.done (끝난 항목), 결과: ~/resume-<모듈>.log
# 시작할 때 이전 실행이 남긴 흔적을 정리한다: 진행 중 파이프라인 실행 중단(cicd), 주입 상태로 남은 Lab 원복.
set -uo pipefail
: "${SID:?}"; source ~/opslab-env.sh; export SID
ROOT=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
MOD=${1:?모듈}; MY="$ROOT/modules/$MOD/module.yaml"
DONE=~/resume-$MOD.done; LOG=~/resume-$MOD.log; touch "$DONE"
LIST=${2:-$(grep -E '^ *- *[a-z]+-[0-9]+ *\|' "$MY" | while IFS='|' read -r lab f n rest; do
  lab=$(sed 's/^ *- *//' <<<"$lab" | xargs); for v in $(seq 1 "$(xargs <<<"$n")"); do echo -n "$lab:$v "; done; done)}

echo "== $(date '+%F %T') 이어 하기 시작 ($(wc -l < "$DONE")개 완료됨)" >> "$LOG"
# 흔적 정리
if [ "$MOD" = cicd ]; then
  for e in $(aws codepipeline list-pipeline-executions --pipeline-name "$SID-cicd-pipeline" --max-items 10 \
      --query "pipelineExecutionSummaries[?status=='InProgress'].pipelineExecutionId" --output text 2>/dev/null); do
    aws codepipeline stop-pipeline-execution --pipeline-name "$SID-cicd-pipeline" --pipeline-execution-id "$e" --abandon --reason "resume cleanup" >/dev/null && echo "  실행 중단 $e" >> "$LOG"
  done
  sleep 20
fi
for lab in $(bash "$ROOT/common/inject.sh" status 2>/dev/null | awk -v m="$MOD-" '$2 ~ "^"m && $3=="injected" {print $2}'); do
  echo "  주입 상태로 남은 $lab 원복" >> "$LOG"; echo y | bash "$ROOT/common/inject.sh" rollback "$lab" >> "$LOG" 2>&1
done
# 아직 안 끝난 첫 항목은 주입 도중 끊겼을 수 있다(기록 없이 장애만 남음) — 그 장애의 원복을 한 번 실행
for item in $LIST; do grep -qx "$item" "$DONE" && continue
  lab=${item%:*}; f=$(grep -E "^ *- *$lab *\|" "$MY" | cut -d'|' -f2 | xargs)
  echo "  미완료 첫 항목 $item 의 원복($f) 선실행" >> "$LOG"
  echo y | LAB=$lab bash "$ROOT/modules/$MOD/faults/$f/rollback.sh" >> "$LOG" 2>&1; break
done
if [ "$MOD" = cicd ]; then   # 마지막 실행이 성공이 아니면 정상 릴리스로 맞춘다
  CICD_NO_LAB=1 source "$ROOT/modules/cicd/lib.sh"
  read -r _ s <<<"$(last_exec)"; [ "$s" = Succeeded ] || echo "  정상 릴리스 재배포: $(redeploy_good)" >> "$LOG"
fi

for item in $LIST; do
  grep -qx "$item" "$DONE" && continue
  lab=${item%:*}; v=${item#*:}
  SKIP_START=1 SKIP_CLEAN=1 DEEP=${DEEP:-90} LABS=$lab VARIANTS=$v bash "$ROOT/tools/test-module.sh" "$MOD" 2>&1 | grep -aE '^(OK|XX)' >> "$LOG"
  echo "$item" >> "$DONE"
done
echo "ALL-DONE $(date '+%F %T')" >> "$LOG"
