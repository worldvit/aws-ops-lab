#!/bin/bash
# AfterInstall — 릴리스 설정(release.env)을 앱 환경 파일에 반영
set -e
R=/etc/app/release/release.env; E=/etc/app/app.env
touch "$E"
while IFS='=' read -r k v; do
  [ -z "$k" ] && continue
  if grep -q "^$k=" "$E"; then sed -i "s|^$k=.*|$k=$v|" "$E"; else echo "$k=$v" >> "$E"; fi
done < "$R"
cat "$E"
