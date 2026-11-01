#!/bin/bash
# rel 따라잡기: start.sh rel full 이 호출 — 1단계 따라하기 명령 모음을 그대로 실행한다(복원 실측은 건너뜀).
SKIP_RESTORE=1 bash "$(dirname "$(readlink -f "$0")")/../../tools/build/rel.sh"
