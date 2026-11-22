#!/bin/bash
# heal selfheal — verify. 실행: bash ~/opslab/modules/heal/faults/selfheal/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "heal selfheal"
