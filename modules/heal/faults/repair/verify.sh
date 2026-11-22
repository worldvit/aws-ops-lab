#!/bin/bash
# heal repair — verify. 실행: bash ~/opslab/modules/heal/faults/repair/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "heal repair"
