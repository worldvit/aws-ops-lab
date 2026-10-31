#!/bin/bash
# iac changeset — rollback. 옛 버킷(Retain 으로 남은)의 객체를 새 버킷으로 복사한다. 스택 이름 규칙(-prod)은 유지.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
need_stack
O=$(load old_bucket); N=$(sres ArtifactBucket)
[ -z "$O" ] || [ "$O" = None ] && O="$SID-iac-artifacts-$ACCT"
if [ "$O" != "$N" ] && aws s3api head-bucket --bucket "$O" 2>/dev/null; then
  aws s3 sync "s3://$O" "s3://$N" --quiet && echo "  s3://$O → s3://$N 복사"
fi
