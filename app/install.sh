#!/bin/bash
# 샘플 앱 설치 스크립트 — 시작 템플릿(Launch Template)의 사용자 데이터에서 실행된다.
# 사용법(사용자 데이터):
#   #!/bin/bash
#   curl -fsSL https://raw.githubusercontent.com/worldvit/aws-ops-lab/main/app/install.sh | bash
set -euo pipefail

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/worldvit/aws-ops-lab/main}"
APP_PORT="${APP_PORT:-8080}"
APP_VERSION="${APP_VERSION:-v1}"

dnf install -y python3-pip
pip3 install --quiet flask==3.0.3 gunicorn==22.0.0 psycopg2-binary==2.9.9 boto3==1.35.36

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
Description=opslab sample app (Flask + gunicorn)
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

# DB 접속정보 갱신기(data 모듈부터): SSM Parameter Store /opslab/app/db/* → /etc/app/db.env (30초마다)
cat > /opt/app/db-env.sh <<'DBENV'
#!/bin/bash
T=$(curl -s -m 2 -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
R=$(curl -s -m 2 -H "X-aws-ec2-metadata-token: $T" http://169.254.169.254/latest/meta-data/placement/region)
P=/opslab/app/db
OUT=$(aws ssm get-parameters --region "$R" --names $P/host $P/reader_host $P/port $P/name $P/user $P/password \
      --query 'Parameters[].[Name,Value]' --output text 2>/dev/null) || exit 0
[ -z "$OUT" ] && { rm -f /etc/app/db.env; exit 0; }
while IFS=$'\t' read -r k v; do k=${k##*/}; echo "DB_${k^^}=$v"; done <<<"$OUT" > /etc/app/db.env.tmp
chmod 600 /etc/app/db.env.tmp && mv /etc/app/db.env.tmp /etc/app/db.env
DBENV
chmod +x /opt/app/db-env.sh
cat > /etc/systemd/system/app-db-env.service <<'DBENV'
[Unit]
Description=refresh DB settings from SSM Parameter Store
[Service]
Type=oneshot
ExecStart=/opt/app/db-env.sh
DBENV
cat > /etc/systemd/system/app-db-env.timer <<'DBENV'
[Unit]
Description=refresh DB settings every 30s
[Timer]
OnBootSec=5s
OnUnitActiveSec=30s
AccuracySec=1s
[Install]
WantedBy=timers.target
DBENV

# CodeDeploy 에이전트(cicd 모듈의 EC2 배포가 사용) — 다른 모듈에는 영향 없음. 실패해도 앱 설치는 계속
( dnf install -y ruby wget >/dev/null 2>&1 &&
  cd /tmp && wget -q "https://aws-codedeploy-ap-northeast-2.s3.ap-northeast-2.amazonaws.com/latest/install" -O cd-install &&
  chmod +x cd-install && ./cd-install auto >/dev/null 2>&1 && systemctl enable --now codedeploy-agent ) || echo "codedeploy-agent 설치 실패" >&2

systemctl daemon-reload
systemctl enable --now app-db-env.timer
systemctl enable --now app.service

# sec 모듈부터: Vault 가 준비되어 있으면(SSM /opslab/sec/vault/addr) Vault Agent·내부 HTTPS 설치 — 새로 뜬 인스턴스도 같은 상태가 된다
R=$(curl -s -m 2 -H "X-aws-ec2-metadata-token: $(curl -s -m 2 -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')" http://169.254.169.254/latest/meta-data/placement/region)
VA=$(aws ssm get-parameter --region "$R" --name /opslab/sec/vault/addr --query Parameter.Value --output text 2>/dev/null || true)
SI=$(aws ssm get-parameter --region "$R" --name /opslab/sec/secret_id --query Parameter.Value --output text 2>/dev/null || true)
if [ -n "$VA" ] && [ "$VA" != None ]; then
  curl -fsSL "$REPO_RAW/app/sec-agent.sh" | VAULT_ADDR="$VA" SECRET_ID="$SI" bash || echo "sec-agent 설치 실패" >&2
fi

# 로컬 확인
for i in $(seq 1 20); do
  if curl -fsS "http://127.0.0.1:${APP_PORT}/health" >/dev/null; then
    echo "app is up on :${APP_PORT}"; exit 0
  fi
  sleep 2
done
echo "app did not start" >&2
exit 1
