#!/bin/bash
# auto session — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
# 영향 범위: v1 앱 서버 보안 그룹(-cmp-app-sg)의 아웃바운드 규칙과 앱 서버 SSM 에이전트 재시작,
#           v2·v3 계정(리전)의 Session Manager 기본 설정 문서 1개(새 버전). 앱 서비스와 다른 서버 설정은 건드리지 않는다.
[ -n "$(asg_ids)" ] || exit 3
V_=$(pick_variant 3)
case $V_ in
  1) # "아웃바운드는 웹(80)만 열면 된다"며 보안 그룹을 조임 → 에이전트가 SSM(443)에 다시 연결하지 못함
     SG=$(aws cloudformation list-exports --query "Exports[?Name=='$SID-cmp-AppSg'].Value" --output text)
     save sg "$SG"
     aws ec2 revoke-security-group-egress --group-id "$SG" --ip-permissions 'IpProtocol=-1,IpRanges=[{CidrIp=0.0.0.0/0}]' >/dev/null || exit 1
     aws ec2 authorize-security-group-egress --group-id "$SG" --ip-permissions 'IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0,Description=web only}]' >/dev/null 2>&1
     # 이미 맺어진 연결은 규칙을 지워도 유지되므로, 에이전트를 재시작해 새로 연결하게 한다(실제 현장에서는 재부팅·에이전트 업데이트 때 드러남)
     ssm_run "$(asg_ids)" "nohup bash -c 'sleep 3; systemctl restart amazon-ssm-agent' >/dev/null 2>&1 & echo scheduled" 30 >/dev/null ;;
  2) # 로그 그룹 이름 오타(sessions → session)
     put_pref "/opslab/$SID/session" || exit 1 ;;
  3) # "로그는 암호화해야 한다"며 암호화 요구를 켬 — 로그 그룹은 KMS 암호화가 아님
     put_pref "$LOGG" || exit 1
     V=$(aws ssm update-document --name "$PREF" --content "$(pref_json "$LOGG" | jq -c '.inputs.cloudWatchEncryptionEnabled=true')" --document-version '$LATEST' --query DocumentDescription.DocumentVersion --output text) || exit 1
     aws ssm update-document-default-version --name "$PREF" --document-version "$V" >/dev/null || exit 1 ;;
esac
record $V_
