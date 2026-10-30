#!/bin/bash
# data 모듈 공통 함수: Aurora 클러스터(<학번>-data-db) 찾기, SQL 실행(loadgen 의 psql), 배경 작업(systemd-run)
# 장애 스크립트는 common/lib.sh 의 SID·LAB 검사를 거친다. probe.sh·verify.sh 는 DATA_NO_LAB=1 로 부른다.
D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
if [ -n "${DATA_NO_LAB:-}" ]; then
  set -uo pipefail; : "${SID:?SID 환경변수에 학번을 넣으세요. 예) source ~/opslab-env.sh}"
  export AWS_REGION="${AWS_REGION:-ap-northeast-2}"
else
  source "$D/../../common/lib.sh"
fi
source "$D/../../common/ssm.sh"
CLUSTER="$SID-data-db"
read -r WRITER_EP READER_EP DB_STATUS CPG <<<"$(aws rds describe-db-clusters --db-cluster-identifier "$CLUSTER" \
  --query 'DBClusters[0].[Endpoint,ReaderEndpoint,Status,DBClusterParameterGroup]' --output text 2>/dev/null)"
WRITER_ID=$(aws rds describe-db-clusters --db-cluster-identifier "$CLUSTER" --query 'DBClusters[0].DBClusterMembers[?IsClusterWriter].DBInstanceIdentifier|[0]' --output text 2>/dev/null)
READER_ID=$(aws rds describe-db-clusters --db-cluster-identifier "$CLUSTER" --query 'DBClusters[0].DBClusterMembers[?!IsClusterWriter].DBInstanceIdentifier|[0]' --output text 2>/dev/null)
ADMIN_PW=$(aws ssm get-parameter --name /opslab/data/admin_password --query Parameter.Value --output text 2>/dev/null)
LOADGEN=$(inst "$SID-base-loadgen")
P=/opslab/app/db

need() { local v; for v in "$@"; do case "${!v:-}" in ""|None) echo "data 모듈 리소스($v)를 찾지 못했습니다. 1단계 구축을 먼저 끝내세요."; exit 3;; esac; done; }
alb_dns() { aws elbv2 describe-load-balancers --names "$SID-cmp-alb" --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null; }
app_ids() { aws ec2 describe-instances --filters Name=tag:Name,Values="$SID-cmp-app" Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId' --output text; }
pget() { aws ssm get-parameter --name "$P/$1" --query Parameter.Value --output text 2>/dev/null; }
pput() { aws ssm put-parameter --name "$P/$1" --type String --overwrite --value "$2" >/dev/null; }

sql() {  # $1=SQL(여러 문장 가능) [$2=DB 이름(기본 opslab)] [$3=접속 호스트(기본 라이터)] → psql -At 출력. loadgen 에서 관리자 계정으로
  local b64; b64=$(printf '%s' "$1" | base64 -w0)
  ssm_run "$LOADGEN" "echo $b64 | base64 -d | PGPASSWORD='$ADMIN_PW' PGCONNECT_TIMEOUT=5 psql -h ${3:-$WRITER_EP} -U opslab_admin -d ${2:-opslab} -At -v ON_ERROR_STOP=1 -f - 2>&1" 90
}
bg_start() {  # $1=작업 이름(systemd 단위) $2=bash 스크립트 — loadgen 에서 배경으로 실행(관리자 암호는 PGPASSWORD)
  local b64; b64=$(printf '%s' "$2" | base64 -w0)
  ssm_run "$LOADGEN" "systemctl stop $1 2>/dev/null; systemctl reset-failed $1 2>/dev/null
echo $b64 | base64 -d > /usr/local/bin/$1.sh
systemd-run --unit $1 --description 'opslab batch' -p LimitNOFILE=65536 --setenv=PGPASSWORD='$ADMIN_PW' \
  --setenv=WRITER=$WRITER_EP --setenv=READER=$READER_EP /bin/bash /usr/local/bin/$1.sh >/dev/null 2>&1
sleep 2; systemctl is-active $1" 60
}
bg_stop() {  # $@=작업 이름들
  ssm_run "$LOADGEN" "for u in $*; do systemctl stop \$u 2>/dev/null; systemctl reset-failed \$u 2>/dev/null; rm -f /usr/local/bin/\$u.sh; done; echo stopped" 60 >/dev/null
}
wait_cluster() {  # 클러스터와 인스턴스가 모두 available 이 될 때까지(최대 $1초, 기본 600)
  local i; for i in $(seq 1 $(( ${1:-600} / 15 ))); do
    s=$(aws rds describe-db-instances --filters Name=db-cluster-id,Values="$CLUSTER" --query 'DBInstances[].DBInstanceStatus' --output text)
    c=$(aws rds describe-db-clusters --db-cluster-identifier "$CLUSTER" --query 'DBClusters[0].Status' --output text)
    [ "$c" = available ] && ! grep -qv available <<<"$(tr '\t' '\n' <<<"$s")" && return 0; sleep 15
  done; return 1
}
