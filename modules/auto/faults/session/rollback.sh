#!/bin/bash
# auto session — rollback. 보안 그룹 아웃바운드 전체 허용 복구 + 에이전트 연결 확인, 접속 기록 설정을 원본으로.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
SG=$(aws cloudformation list-exports --query "Exports[?Name=='$SID-cmp-AppSg'].Value" --output text)
aws ec2 authorize-security-group-egress --group-id "$SG" --ip-permissions 'IpProtocol=-1,IpRanges=[{CidrIp=0.0.0.0/0}]' >/dev/null 2>&1
aws ec2 revoke-security-group-egress --group-id "$SG" --ip-permissions 'IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0}]' >/dev/null 2>&1
echo "  보안 그룹 $SG 아웃바운드 전체 허용"
put_pref "$LOGG"; [ "$(pref_group)" = "$LOGG" ] && echo "  접속 기록 설정 → $LOGG"
# 연결이 끊긴 서버는 에이전트가 재시도하며 다시 붙는다(최대 수 분). PingStatus 는 몇 분 늦게 바뀌어
# 끊긴 서버도 한동안 Online 으로 보이므로, "원복 이후에 실제로 명령이 전달되는지"로 판정한다. 6분 안에 안 되면 재부팅
for i in $(seq 1 6); do bad=""
  for x in $(asg_ids); do
    c=$(aws ssm send-command --instance-ids "$x" --document-name AWS-RunShellScript --parameters 'commands=["true"]' --timeout-seconds 30 --query Command.CommandId --output text 2>/dev/null)
    st=Pending; for _ in 1 2 3 4 5 6; do sleep 5; st=$(aws ssm get-command-invocation --command-id "$c" --instance-id "$x" --query Status --output text 2>/dev/null); [ "$st" = Success ] && break; done
    [ "$st" = Success ] || bad="$bad $x"
  done
  [ -z "$bad" ] && break
done
[ -n "$bad" ] && aws ec2 reboot-instances --instance-ids $bad && echo "  재부팅:$bad" && sleep 90
exit 0
