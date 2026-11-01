#!/bin/bash
# rel backup — rollback. 보존 7일, 삭제 방지 켬.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
aws rds modify-db-cluster --db-cluster-identifier "$CLUSTER" --backup-retention-period 7 --deletion-protection --apply-immediately   --query 'DBCluster.[BackupRetentionPeriod,DeletionProtection]' --output text
