#!/bin/bash
# net nat-port — rollback. 모든 앱 서버와 loadgen 에서 배치 프로세스를 멈추고 포트 범위를 기본값으로 되돌린다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
need LOADGEN
IDS="$(app_ids) $LOADGEN"
ssm_run "$IDS" "systemctl stop partner-sync 2>/dev/null; systemctl reset-failed partner-sync 2>/dev/null; rm -f /usr/local/bin/partner-sync.py
sysctl -qw net.ipv4.ip_local_port_range='32768 60999'; echo \"\$(hostname) port80=\$(ss -Htn state established '( dport = :80 )' | wc -l)\"" 60 | sed 's/^/  /'
echo "  배치 프로세스 중지 (NAT 지표가 0으로 돌아오기까지 1~2분)"
