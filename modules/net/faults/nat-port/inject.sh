#!/bin/bash
# net nat-port — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: 앱 서버 또는 loadgen 에 연결을 많이 여는 배치 프로세스(partner-sync)를 띄운다. AWS 설정은 바꾸지 않는다.
need NAT LOADGEN
DNS=$(alb_dns); IP=$(getent ahostsv4 "$DNS" | awk '{print $1}' | sort -u | head -1)
[ -n "$IP" ] || { echo "ALB 주소를 찾지 못했습니다"; exit 1; }
V=$(pick_variant 2)
case $V in
  1) IDS=$(app_ids); N=32000 ;;     # 앱 서버 2대 × 32,000
  2) IDS=$LOADGEN;   N=62000 ;;     # loadgen 1대 × 62,000
esac
[ -n "$IDS" ] || { echo "대상 서버가 없습니다"; exit 1; }
save target "$IP"
ssm_run "$IDS" "set -e
curl -fsSL https://raw.githubusercontent.com/worldvit/aws-ops-lab/main/modules/net/faults/nat-port/pool.py -o /usr/local/bin/partner-sync.py
sysctl -qw net.ipv4.ip_local_port_range='1024 65535'
systemctl stop partner-sync 2>/dev/null || true; systemctl reset-failed partner-sync 2>/dev/null || true
systemd-run --unit partner-sync --description 'partner sync batch' -p LimitNOFILE=200000 /usr/bin/python3 /usr/local/bin/partner-sync.py $IP $N
sleep 2; systemctl is-active partner-sync" 60 | grep -q active || exit 1
record $V
