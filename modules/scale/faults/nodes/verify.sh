#!/bin/bash
# scale nodes — verify. 실행: bash ~/opslab/modules/scale/faults/nodes/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "scale nodes"
