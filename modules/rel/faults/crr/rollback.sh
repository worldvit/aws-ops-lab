#!/bin/bash
# rel crr — rollback. 복제 역할 정책·도쿄 버전 관리·복제 규칙을 원본으로. (장애 중 올린 파일은 복제되지 않은 채 남는다 — 재복제는 6단계 참고)
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
put_repl_policy && echo "  복제 역할 정책 원본"
aws s3api put-bucket-versioning --bucket "$DR" --region "$DR_REGION" --versioning-configuration Status=Enabled && echo "  도쿄 버전 관리 Enabled"
aws s3api put-bucket-replication --bucket "$SRC" --replication-configuration "$(repl_json)" && echo "  복제 규칙: 전체 객체"
exit 0
