#!/bin/bash
# data failover-endpoint 판정 — 앱 쓰기, 접속정보가 클러스터 엔드포인트인지, 클러스터 상태. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start failover-endpoint
echo "[1] 앱 → DB"; chk_app /db "쓰기(/db)"
echo "[2] 클러스터·접속정보"; chk_cluster
finish
