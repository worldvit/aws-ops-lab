#!/bin/bash
# 리허설용(작성자) — 진행 중인 시험이 끝나면 auto 마무리 재시험 → auto 고유 구성 정리 → rel 1-5 훈련 → rel baseline → rel 전체 시험을 차례로 돌린다.
#   setsid nohup bash ~/opslab/tools/rehearse-chain.sh > ~/chain.log 2>&1 &
source ~/opslab-env.sh; export SID
while pgrep -f test-resume.sh >/dev/null; do sleep 20; done
echo "== $(date +%T) auto-2:2 재시험"; sed -i '/^auto-2:2$/d' ~/resume-auto.done
bash ~/opslab/tools/test-resume.sh auto "auto-2:2"; tail -2 ~/resume-auto.log
echo "== $(date +%T) auto 고유 구성 정리"
bash ~/opslab/modules/auto/cleanup.sh
aws cloudformation delete-stack --stack-name "$SID-auto-env"; aws cloudformation wait stack-delete-complete --stack-name "$SID-auto-env"; echo "  auto-env 삭제"
echo "== $(date +%T) rel 1-5·1-6"
B=~/opslab/tools/build/rel.sh; (sed -n '1,8p' $B; sed -n '/^echo "== 1-5/,$p' $B) > ~/rel-part2.sh
bash ~/rel-part2.sh > ~/rel-build2.log 2>&1; echo "  BUILD2-EXIT=$?"; tail -5 ~/rel-build2.log
echo "== $(date +%T) rel baseline"; bash ~/opslab/modules/rel/baseline/verify.sh > ~/rel-base.log 2>&1; tail -3 ~/rel-base.log
echo "== $(date +%T) rel 전체 시험"; rm -f ~/resume-rel.done ~/resume-rel.log
bash ~/opslab/tools/test-resume.sh rel; tail -12 ~/resume-rel.log
echo "CHAIN-DONE $(date +%T)"
