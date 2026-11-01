#!/bin/bash
# rel crr — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: 복제 역할 인라인 정책(v1), 도쿄 버킷 버전 관리(v2), 서울 버킷 복제 규칙(v3) 중 하나. 이미 복제된 파일은 건드리지 않는다.
aws s3api get-bucket-replication --bucket "$SRC" >/dev/null 2>&1 || exit 3
V_=$(pick_variant 3)
case $V_ in
  1) # 권한 정리 중 복제 역할에서 "도쿄에 쓰기" 권한이 빠짐
     P=$(aws iam get-role-policy --role-name "$SID-rel-repl-role" --policy-name replication --query PolicyDocument --output json) || exit 1
     aws iam put-role-policy --role-name "$SID-rel-repl-role" --policy-name replication        --policy-document "$(jq -c '.Statement |= map(select(.Sid != "WriteReplica"))' <<<"$P")" || exit 1 ;;
  2) # 비용을 줄인다며 도쿄 버킷의 버전 관리를 일시 중지
     aws s3api put-bucket-versioning --bucket "$DR" --region "$DR_REGION" --versioning-configuration Status=Suspended || exit 1 ;;
  3) # "보관용(archive/)만 복제하면 된다"며 복제 규칙에 접두사를 넣음
     aws s3api put-bucket-replication --bucket "$SRC" --replication-configuration "$(repl_json archive/)" || exit 1 ;;
esac
record $V_
