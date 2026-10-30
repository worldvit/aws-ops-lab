#!/bin/bash
# 샘플 앱 설치 스크립트 — 시작 템플릿(Launch Template)의 사용자 데이터에서 실행된다.
# 사용법(사용자 데이터):
#   #!/bin/bash
#   curl -fsSL https://raw.githubusercontent.com/worldvit/megazoncloud-matchingday-sk/main/app/install.sh | bash
set -euo pipefail

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/worldvit/megazoncloud-matchingday-sk/main}"
APP_PORT="${APP_PORT:-8080}"
APP_VERSION="${APP_VERSION:-v1}"

dnf install -y python3-pip
pip3 install --quiet flask==3.0.3 gunicorn==22.0.0

mkdir -p /opt/app /etc/app
curl -fsSL "$REPO_RAW/app/app.py" -o /opt/app/app.py

# 환경변수 파일: 이미 있으면 덮어쓰지 않는다(장애 실습 중 변경 내용 보존)
if [ ! -f /etc/app/app.env ]; then
  cat > /etc/app/app.env <<EOF
APP_PORT=$APP_PORT
APP_VERSION=$APP_VERSION
APP_ERROR_RATE=0
EOF
fi

cat > /etc/systemd/system/app.service <<'EOF'
[Unit]
Description=skons-ops sample app (Flask + gunicorn)
After=network-online.target
Wants=network-online.target

[Service]
EnvironmentFile=/etc/app/app.env
WorkingDirectory=/opt/app
ExecStart=/usr/local/bin/gunicorn -w 2 --threads 4 --timeout 35 -b 0.0.0.0:${APP_PORT} --access-logfile - app:app
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now app.service

# 로컬 확인
for i in $(seq 1 20); do
  if curl -fsS "http://127.0.0.1:${APP_PORT}/health" >/dev/null; then
    echo "app is up on :${APP_PORT}"; exit 0
  fi
  sleep 2
done
echo "app did not start" >&2
exit 1
