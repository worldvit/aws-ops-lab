#!/bin/bash
# heal canary — verify. 실행: bash ~/opslab/modules/heal/faults/canary/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "heal canary"
