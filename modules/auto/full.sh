#!/bin/bash
# auto 따라잡기: start.sh auto full 이 호출 — 1단계 따라하기 명령 모음을 그대로 실행한다.
bash "$(dirname "$(readlink -f "$0")")/../../tools/build/auto.sh"
