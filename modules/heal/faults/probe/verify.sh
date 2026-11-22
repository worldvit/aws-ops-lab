#!/bin/bash
# heal probe — verify. 실행: bash ~/opslab/modules/heal/faults/probe/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "heal probe"
