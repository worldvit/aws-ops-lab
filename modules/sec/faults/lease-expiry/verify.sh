#!/bin/bash
# sec lease-expiry 판정 — DB 쓰기, Agent, DB 역할 유효기간, 앱 정책. 실행 위치: CloudShell
source "$(dirname "$(readlink -f "$0")")/../../check.sh"
start lease-expiry
echo "[1] 앱 → DB"; chk_app /db "DB 쓰기(/db) — 동적 자격증명"
echo "[2] 자격증명 공급"; chk_agent; chk_vpolicy
t=$(vrun "vault read -format=json database/roles/app | jq -r '.data | \"\(.default_ttl) \(.max_ttl)\"'" 30)
read -r d m <<<"$t"
[ "${d:-0}" -ge 3600 ] 2>/dev/null && [ "${m:-0}" -ge 86400 ] 2>/dev/null && ok "DB 역할 유효기간 default ${d}s / max ${m}s" || ng "DB 역할 유효기간 default ${d:-?}s / max ${m:-?}s (1시간/24시간 이상이어야 함)"
finish
