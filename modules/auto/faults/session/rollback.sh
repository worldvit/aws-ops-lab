#!/bin/bash
# auto session — rollback. 보안 그룹 아웃바운드 전체 허용 복구 + 에이전트 연결 확인, 접속 기록 설정을 원본으로.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
SG=$(aws cloudformation list-exports --query "Exports[?Name=='$SID-cmp-AppSg'].Value" --output text)
aws ec2 authorize-security-group-egress --group-id "$SG" --ip-permissions 'IpProtocol=-1,IpRanges=[{CidrIp=0.0.0.0/0}]' >/dev/null 2>&1
aws ec2 revoke-security-group-egress --group-id "$SG" --ip-permissions 'IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0}]' >/dev/null 2>&1
echo "  보안 그룹 $SG 아웃바운드 전체 허용"
put_pref "$LOGG"; [ "$(pref_group)" = "$LOGG" ] && echo "  접속 기록 설정 → $LOGG"
# 연결이 끊긴 서버는 에이전트가 재시도하며 다시 붙는다(최대 수 분). 5분 안에 안 붙으면 재부팅
for i in $(seq 1 30); do bad=""; for x in $(asg_ids); do [ "$(ping_of $x)" = Online ] || bad="$bad $x"; done; [ -z "$bad" ] && break; sleep 10; done
[ -n "$bad" ] && aws ec2 reboot-instances --instance-ids $bad && echo "  재부팅:$bad"
exit 0
