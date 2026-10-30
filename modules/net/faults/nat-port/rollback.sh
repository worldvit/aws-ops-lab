#!/bin/bash
# net nat-port — rollback. 모든 앱 서버와 loadgen 에서 배치 프로세스를 멈추고 포트 범위를 기본값으로 되돌린다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
need LOADGEN
IDS="$(app_ids) $LOADGEN"
ssm_run "$IDS" "systemctl stop partner-sync 2>/dev/null; systemctl reset-failed partner-sync 2>/dev/null; rm -f /usr/local/bin/partner-sync.py
sysctl -qw net.ipv4.ip_local_port_range='32768 60999'; echo \"\$(hostname) port80=\$(ss -Htn state established '( dport = :80 )' | wc -l)\"" 60 | sed 's/^/  /'
echo "  배치 프로세스 중지 (NAT 지표가 0으로 돌아오기까지 1~2분)"
# NAT 는 닫힌 연결의 포트를 바로 돌려주지 않는다(리허설: 멈춘 뒤 2~3분 동안 일부 실패). 회복될 때까지 최대 6분 기다린다.
IP=$(load target); DNS=$(alb_dns)
if [ -n "$IP" ] && [ "$IP" != None ]; then
  for i in $(seq 1 12); do
    r=$(ssm_run "$LOADGEN" "ok=0; for i in 1 2 3 4 5; do c=\$(curl -s -o /dev/null -m 4 --connect-timeout 3 -w '%{http_code}' --resolve $DNS:80:$IP http://$DNS/health); [ \"\$c\" = 200 ] && ok=\$((ok+1)); done; echo \$ok" 40 | tr -dc 0-9)
    [ "$r" = 5 ] && { echo "  ALB $IP 연결 회복 확인 (5/5)"; break; }
    echo "  NAT 포트 반환 대기 중... ($i/12, 성공 ${r:-0}/5)"; sleep 30
  done
fi
