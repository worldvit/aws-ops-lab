#!/bin/bash
# cicd bad-release 판정 — 배포 안전장치가 켜져 있고, 마지막 실행이 성공했으며, 두 서비스가 오류 없이 같은 릴리스. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start bad-release
echo "[1] 배포 안전장치"; chk_guard
echo "[2] 파이프라인"; chk_last
echo "[3] 서비스 (오류 없이 5/5)"; chk_version
finish
