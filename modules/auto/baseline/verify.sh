#!/bin/bash
# auto 정상 상태 정의(2단계) 판정. 실행 위치: CloudShell (2~4분 — 런북을 실제로 두 번 실행한다)
source "$(dirname "$(readlink -f "$0")")/../check.sh"
start baseline
echo "[0] 서비스"; chk_service
echo "[1] 접속과 접속 기록(Session Manager)"; chk_online; chk_session
echo "[2] 동시 조치(Run Command)"; chk_runcmd
echo "[3] 런북(Automation)과 안전장치"; chk_runbook
echo "[4] 자동 복구 연결(알람 → EventBridge → 런북)"; chk_chain; chk_e2e
echo "[6] 패치 유지관리 기간"; chk_mw
echo "[7] DNS 자동 전환(Route 53)"; chk_failover
finish
