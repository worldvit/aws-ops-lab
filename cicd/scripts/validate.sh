#!/bin/bash
# ValidateService — 이 서버가 새 버전으로 살아났는지 확인 (실패하면 배포가 이 서버에서 멈춘다)
want=$(sed -n 's/^APP_VERSION=//p' /etc/app/release/release.env)
for i in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:8080/health >/dev/null 2>&1; then
    got=$(curl -s http://127.0.0.1:8080/health | python3 -c 'import sys,json; print(json.load(sys.stdin).get("version",""))' 2>/dev/null)
    echo "health ok, version=$got (want $want)"
    [ "$got" = "$want" ] && exit 0
  fi
  sleep 2
done
echo "validate failed: /health not ok or version != $want"; exit 1
