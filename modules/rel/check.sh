#!/bin/bash
# rel 모듈 verify 공통. verify.sh 들이 source 한다.
REL_NO_LAB=1 source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"
PASS=0; FAIL=0
ok() { echo "  [PASS] $*"; PASS=$((PASS+1)); }
ng() { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }
start() { echo "== $(date '+%F %T') 정상 상태 판정: $SID / rel $1 =="; }

chk_service() {  # /api 20번, /db 10번 모두 200 (순간 오류를 피하려고 한 번 더 시도)
  local a d; a=$(ok_count /api 20); d=$(ok_count /db 10)
  if [ "$a" != 20 ] || [ "$d" != 10 ]; then sleep 15; a=$(ok_count /api 20); d=$(ok_count /db 10); fi
  [ "$a" = 20 ] && ok "/api 20/20" || ng "/api $a/20"
  [ "$d" = 10 ] && ok "/db 10/10 (DB 쓰기)" || ng "/db $d/10 — DB 쓰기 실패 섞임"
}
chk_crr() {  # 버전 관리·복제 규칙·실제 복제
  local v1 v2 r p
  v1=$(aws s3api get-bucket-versioning --bucket "$SRC" --query Status --output text 2>/dev/null)
  v2=$(aws s3api get-bucket-versioning --bucket "$DR" --region "$DR_REGION" --query Status --output text 2>/dev/null)
  [ "$v1" = Enabled ] && [ "$v2" = Enabled ] && ok "버전 관리: 서울 $v1 / 도쿄 $v2" || ng "버전 관리: 서울 ${v1:-없음} / 도쿄 ${v2:-없음} (둘 다 Enabled 여야 복제됨)"
  r=$(aws s3api get-bucket-replication --bucket "$SRC" --output json 2>/dev/null | jq -r '.ReplicationConfiguration.Rules[0] | "\(.Status) 접두사=\(.Filter.Prefix // "") \(.Destination.Bucket)"')
  [ "$r" = "Enabled 접두사= arn:aws:s3:::$DR" ] && ok "복제 규칙: 전체 객체 → $DR" || ng "복제 규칙: ${r:-없음} (기대: Enabled, 접두사 없음, 도쿄 버킷)"
  read -r p st <<<"$(crr_probe 180)"
  [ "$p" != FAIL ] && ok "복제 시험: ${p}초 만에 도쿄 도착 (원본 상태 $st)" || ng "복제 시험: 180초 안에 도쿄에 없음 (원본 복제 상태 ${st:-없음})"
}
chk_az() {  # 두 AZ 에 걸친 구성
  local s n; s=$(asg_subnets); n=$(for x in $s; do az_of "$x"; done | sort -u | wc -l)
  [ "$n" -ge 2 ] && ok "ASG 서브넷 ${n}개 AZ ($s)" || ng "ASG 서브넷이 AZ ${n}개뿐 ($s)"
  n=$(aws rds describe-db-instances --filters Name=db-cluster-id,Values="$CLUSTER" --query 'DBInstances[].AvailabilityZone' --output text | tr '\t' '\n' | sort -u | wc -l)
  [ "$n" -ge 2 ] && ok "DB 인스턴스 ${n}개 AZ ($(member_azs))" || ng "DB 인스턴스가 AZ ${n}개뿐 ($(member_azs))"
}
chk_drill() {  # 훈련 템플릿(단절 + DB 장애 조치 + 중단 조건)
  local t a; t=$(aws fis list-experiment-templates --query "experimentTemplates[?tags.Name=='$TPL_NAME'].id|[0]" --output text 2>/dev/null)
  [ -n "$t" ] && [ "$t" != None ] || { ng "AZ 훈련 템플릿($TPL_NAME) 없음"; return; }
  a=$(aws fis get-experiment-template --id "$t" --query 'experimentTemplate.[actions.*.actionId, stopConditions[0].source]' --output json | jq -r 'flatten|sort|join(",")')
  [ "$a" = "aws:cloudwatch:alarm,aws:network:disrupt-connectivity,aws:rds:failover-db-cluster" ] && ok "AZ 훈련 템플릿 $t: 단절 + DB 장애 조치 + 중단 조건" || ng "AZ 훈련 템플릿 구성: $a"
}
chk_cost() {  # 과대·유휴 리소스 없음
  local s x
  s=$(asg_size); [ "$s" = 2/2/4 ] && ok "ASG 최소/희망/최대 $s" || ng "ASG 최소/희망/최대 $s (기준 2/2/4)"
  x=$(aws ec2 describe-instances --filters Name=tag:Owner,Values="$SID" Name=instance-state-name,Values=running,stopped \
      --query "Reservations[].Instances[?!(Tags[?Key=='aws:autoscaling:groupName'])].[Tags[?Key=='Name']|[0].Value,InstanceType]" --output text | grep -v -- "-base-loadgen" | tr '\t\n' ' ')
  [ -z "${x// /}" ] && ok "ASG·부하 서버 외 EC2 없음" || ng "ASG·부하 서버 외 EC2: $x"
  x=$(aws ec2 describe-volumes --filters Name=tag:Owner,Values="$SID" Name=status,Values=available --query 'Volumes[].[VolumeId,Size]' --output text | tr '\t\n' ' ')
  [ -z "${x// /}" ] && ok "연결 안 된 EBS 볼륨 없음" || ng "연결 안 된 EBS 볼륨: $x(GB)"
  x=$(aws ec2 describe-addresses --filters Name=tag:Owner,Values="$SID" --query 'Addresses[?AssociationId==null].[PublicIp]' --output text | xargs)
  [ -z "$x" ] && ok "놀고 있는 탄력적 IP 없음" || ng "연결 안 된 탄력적 IP: $x"
  x=$(aws ec2 describe-nat-gateways --filter Name=tag:Owner,Values="$SID" Name=state,Values=available,pending --query 'length(NatGateways)' --output text)
  [ "$x" = 1 ] && ok "NAT 게이트웨이 1개" || ng "NAT 게이트웨이 ${x}개 (기준 1)"
}
chk_backup() {  # 보존 7일 이상, 삭제 방지, RPO(복원 가능한 최근 시각) 10분 이내
  local r p l age
  read -r r p l <<<"$(aws rds describe-db-clusters --db-cluster-identifier "$CLUSTER" --query 'DBClusters[0].[BackupRetentionPeriod,DeletionProtection,LatestRestorableTime]' --output text)"
  [ "${r:-0}" -ge 7 ] && ok "백업 보존 ${r}일" || ng "백업 보존 ${r}일 (기준 7일 이상)"
  [ "$p" = True ] && ok "삭제 방지 켜짐" || ng "삭제 방지 $p"
  age=$(( $(date +%s) - $(date -d "$l" +%s) ))
  [ "$age" -le 600 ] && ok "복원 가능한 최근 시각: ${age}초 전 (RPO 10분 이내)" || ng "복원 가능한 최근 시각이 ${age}초 전"
}
finish() {
  echo "== 결과: PASS $PASS / FAIL $FAIL =="
  if [ "$FAIL" -eq 0 ]; then echo "판정: 정상 (verify 통과) — 기록표에 '복구 완료 시각'과 '통과'를 적으세요"; exit 0
  else echo "판정: 비정상"; exit 1; fi
}
