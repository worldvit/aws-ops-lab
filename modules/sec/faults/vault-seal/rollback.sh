#!/bin/bash
# sec vault-seal — rollback. 손상된 키 조각을 되돌리고, 유효한 키 조각으로 잠금 해제한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
vneed
O=$(aws ssm get-parameter --name "$STATE/unseal-1" --with-decryption --query Parameter.Value --output text 2>/dev/null)
if [ -n "$O" ] && [ "$O" != None ]; then
  aws ssm put-parameter --name $V/unseal-1 --type SecureString --overwrite --value "$O" >/dev/null && echo "  키 조각 1 복원"
  aws ssm delete-parameter --name "$STATE/unseal-1" 2>/dev/null
fi
vrun "systemctl is-active -q vault || systemctl start vault; sleep 2
for n in 1 2 3; do
  vault status >/dev/null 2>&1 && break
  vault operator unseal \$(aws ssm get-parameter --name /opslab/sec/vault/unseal-\$n --with-decryption --query Parameter.Value --output text) >/dev/null 2>&1
done
vault status | grep -E '^Sealed'" 60 | sed 's/^/  /'
