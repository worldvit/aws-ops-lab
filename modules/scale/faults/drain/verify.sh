#!/bin/bash
# scale drain — verify. 실행: bash ~/opslab/modules/scale/faults/drain/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "scale drain"
