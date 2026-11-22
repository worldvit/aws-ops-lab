#!/bin/bash
# heal disrupt — verify. 실행: bash ~/opslab/modules/heal/faults/disrupt/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "heal disrupt"
