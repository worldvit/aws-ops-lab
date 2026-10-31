#!/bin/bash
# cicd 따라잡기: start.sh cicd full 이 호출 — 1단계 따라하기 명령 모음을 그대로 실행한다(GitHub 연결 승인은 사람이 콘솔에서).
bash "$(dirname "$(readlink -f "$0")")/../../tools/build/cicd.sh"
