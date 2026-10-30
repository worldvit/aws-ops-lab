#!/bin/bash
# 장애 스크립트 공통 함수 (모든 모듈). 모듈의 lib.sh 가 먼저 source 한다.
# common/inject.sh 가 SID·LAB 을 정해 호출한다. 모든 변경은 태그 Course=opslab 이 붙은 리소스에만 한다.
set -uo pipefail
: "${SID:?SID 환경변수가 필요합니다}"; : "${LAB:?LAB 환경변수가 필요합니다}"
export AWS_REGION="${AWS_REGION:-ap-northeast-2}"
STATE="/opslab/injections/$LAB"        # 이 Lab의 주입 기록(SSM Parameter Store) 경로

pick_variant() { echo "${VARIANT:-$(( (RANDOM % $1) + 1 ))}"; }          # 1..$1 중 무작위
save()   { aws ssm put-parameter --name "$STATE/$1" --type String --value "$2" --overwrite >/dev/null; }  # 원복용 이전 값
load()   { aws ssm get-parameter --name "$STATE/$1" --query Parameter.Value --output text 2>/dev/null; }
record() { save variant "$1"; }                                          # 변형 번호
