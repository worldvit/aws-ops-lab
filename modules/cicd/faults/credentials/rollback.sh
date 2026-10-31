#!/bin/bash
# cicd credentials — rollback. 파이프라인 역할의 거부 정책을 지우고 실패한 실행을 다시 돌린다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
need_pipe
del_deny "$SID-cicd-pipeline-role"; echo "  파이프라인 역할 거부 정책 삭제"
sleep 30
E=$(load exec); r=$(retry_exec "$E"); echo "  실행 ${E:0:8} 다시 실행: $r"
[ "$r" = Succeeded ] || { r=$(redeploy_good); echo "  정상 릴리스 재배포: $r"; }
