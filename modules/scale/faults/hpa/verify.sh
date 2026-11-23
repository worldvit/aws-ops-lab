#!/bin/bash
# scale hpa — verify. 실행: bash ~/opslab/modules/scale/faults/hpa/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "scale hpa"
