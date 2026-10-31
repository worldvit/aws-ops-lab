#!/bin/bash
# cicd build-fail 판정 — 빌드 설정이 정상이고, 마지막 실행이 성공해 두 서비스가 기록된 릴리스로 응답. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start build-fail
echo "[1] 빌드 설정"
read -r p b <<<"$(aws codebuild batch-get-projects --names "$PROJ" --query 'projects[0].[environment.privilegedMode,source.buildspec]' --output text)"
[ "$p" = True ] && ok "privilegedMode=true (도커 빌드 가능)" || ng "privilegedMode=$p"
[ "$b" = cicd/buildspec.yml ] && ok "buildspec=$b" || ng "buildspec=$b (기대 cicd/buildspec.yml)"
aws iam get-role-policy --role-name "$SID-cicd-build-role" --policy-name ecr-push >/dev/null 2>&1 && ok "빌드 역할 ecr-push 정책 있음" || ng "빌드 역할 ecr-push 정책 없음"
echo "[2] 파이프라인"; chk_last
echo "[3] 서비스"; chk_version
finish
