"""Ops Lab(AWS 인프라 운영 장애 대응 실습) — 샘플 앱 (모든 모듈 공통)

경로
  /health  헬스체크 (ALB 타깃 그룹이 사용)
  /api     일반 응답
  /db      DB 쓰기·조회 (data 모듈부터, ?ro=1 은 리더에서 읽기)
  /slow    지연 응답 (?sec=N, 최대 30초)
  /secret  Secrets Manager 비밀(외부 연동 키) 읽기 (sec 모듈부터)
  /note    Vault Transit 암호화·복호화 (sec 모듈부터) — 새 메모를 암호화해 저장하고, 가장 오래된 메모를 복호화

환경변수 (/etc/app/app.env 에서 읽음)
  APP_PORT        수신 포트 (기본 8080)
  APP_VERSION     응답에 표시할 버전 문자열 (Day 6 배포 실습에서 사용)
  APP_ERROR_RATE  /api 가 500을 반환할 확률 0.0~1.0 (기본 0)
  DB_HOST, DB_READER_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD   DB 접속정보
                  (data 모듈: /etc/app/db.env 를 요청마다 읽음 — SSM /opslab/app/db/* 에서 30초마다 갱신)
                  (sec 모듈: /etc/app/db-cred.env 의 DB_USER·DB_PASSWORD 가 우선 — Vault Agent 가 동적 자격증명으로 갱신)
  VAULT_PROXY     Vault Agent API 프록시 주소 (sec 모듈, 기본 http://127.0.0.1:8100)
  APP_SECRET_ID   Secrets Manager 비밀 이름 (sec 모듈, <학번>/sec/app — app/sec-agent.sh 가 app.env 에 넣음)
"""
import os
import random
import socket
import time

from flask import Flask, jsonify, request

app = Flask(__name__)

HOSTNAME = socket.gethostname()
STARTED_AT = time.time()


def _base():
    return {
        "host": HOSTNAME,
        "version": os.environ.get("APP_VERSION", "v1"),
        "uptime_sec": int(time.time() - STARTED_AT),
    }


@app.route("/health")
def health():
    return jsonify(status="ok", **_base())


@app.route("/api")
def api():
    rate = float(os.environ.get("APP_ERROR_RATE", "0") or 0)
    if random.random() < rate:
        return jsonify(status="error", message="internal error", **_base()), 500
    return jsonify(status="ok", message="hello from opslab", **_base())


@app.route("/slow")
def slow():
    try:
        sec = min(max(float(request.args.get("sec", "1")), 0), 30)
    except ValueError:
        sec = 1
    time.sleep(sec)
    return jsonify(status="ok", slept_sec=sec, **_base())


DB_ENV_FILE = "/etc/app/db.env"   # data 모듈: SSM Parameter Store(/opslab/app/db/*)에서 30초마다 갱신되는 접속정보
DB_CRED_FILE = "/etc/app/db-cred.env"   # sec 모듈: Vault Agent 가 쓰는 동적 자격증명(있으면 우선)


def _db_conf():
    """접속정보: /etc/app/db.env(KEY=VALUE)를 요청마다 읽고, 없으면 프로세스 환경변수."""
    conf = {k: os.environ.get(k, "") for k in ("DB_HOST", "DB_READER_HOST", "DB_PORT", "DB_NAME", "DB_USER", "DB_PASSWORD")}
    for path in (DB_ENV_FILE, DB_CRED_FILE):
        try:
            with open(path) as f:
                for line in f:
                    if "=" in line and not line.startswith("#"):
                        k, v = line.rstrip("\n").split("=", 1)
                        conf[k] = v
        except OSError:
            pass
    return conf


@app.route("/db")
def db():
    """기본: 쓰기(라이터) — hits 에 1행 넣고 개수·시각·라이터 여부를 돌려준다.
    ?ro=1: 읽기(리더 엔드포인트) — 가장 최근 쓰기 시각과 개수(복제 지연 관찰용)."""
    c = _db_conf()
    ro = request.args.get("ro") == "1"
    host = (c.get("DB_READER_HOST") or c.get("DB_HOST")) if ro else c.get("DB_HOST")
    if not host:
        return jsonify(status="not_configured", message="DB_HOST is not set (data 모듈부터 사용)", **_base()), 503
    try:
        import psycopg2

        conn = psycopg2.connect(host=host, port=int(c.get("DB_PORT") or 5432), dbname=c.get("DB_NAME") or "opslab",
                                user=c.get("DB_USER") or "app", password=c.get("DB_PASSWORD") or "", connect_timeout=3)
        try:
            with conn, conn.cursor() as cur:
                if ro:
                    cur.execute("select count(*), max(at), now(), pg_is_in_recovery() from hits")
                    n, last, now, rec = cur.fetchone()
                    lag = (now - last).total_seconds() if last else None
                    return jsonify(status="ok", mode="read", rows=n, last_write=str(last), db_time=str(now),
                                   staleness_sec=lag, db_reader=rec, endpoint=host, **_base())
                cur.execute("create table if not exists hits (id bigserial primary key, at timestamptz default now(), host text)")
                cur.execute("insert into hits(host) values (%s)", (HOSTNAME,))
                cur.execute("select count(*), now(), pg_is_in_recovery() from hits")
                n, now, rec = cur.fetchone()
            return jsonify(status="ok", mode="write", rows=n, db_time=str(now), db_reader=rec, endpoint=host, **_base())
        finally:
            conn.close()
    except Exception as exc:  # noqa: BLE001
        return jsonify(status="error", message=str(exc).strip()[:200], endpoint=host, **_base()), 500


@app.route("/secret")
def secret():
    """Secrets Manager 비밀을 읽는다(앱 EC2 역할 권한 + KMS 키 정책이 모두 맞아야 성공). 값은 길이만 보여 준다."""
    sid = os.environ.get("APP_SECRET_ID", "")
    if not sid:
        return jsonify(status="not_configured", message="APP_SECRET_ID is not set (sec 모듈부터 사용)", **_base()), 503
    try:
        import json
        import boto3

        sm = boto3.client("secretsmanager", region_name=os.environ.get("AWS_REGION", "ap-northeast-2"))
        v = json.loads(sm.get_secret_value(SecretId=sid)["SecretString"])
        return jsonify(status="ok", secret_id=sid, api_key_len=len(v.get("api_key", "")), **_base())
    except Exception as exc:  # noqa: BLE001
        return jsonify(status="error", message=str(exc).strip()[:300], secret_id=sid, **_base()), 500


def _vault(path, body):
    import json
    import urllib.request

    url = os.environ.get("VAULT_PROXY", "http://127.0.0.1:8100").rstrip("/") + "/v1/" + path
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=3) as r:
            return json.loads(r.read())["data"]
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"vault {path}: HTTP {e.code} {e.read().decode()[:200]}") from None


@app.route("/note")
def note():
    """Vault Transit(키 orders)로 새 메모를 암호화해 notes 에 저장하고, 가장 오래된 메모(키 버전 1로 암호화)를 복호화한다."""
    import base64

    c = _db_conf()
    if not c.get("DB_HOST"):
        return jsonify(status="not_configured", message="DB_HOST is not set", **_base()), 503
    try:
        import psycopg2

        ct = _vault("transit/encrypt/orders", {"plaintext": base64.b64encode(f"note from {HOSTNAME}".encode()).decode()})["ciphertext"]
        conn = psycopg2.connect(host=c["DB_HOST"], port=int(c.get("DB_PORT") or 5432), dbname=c.get("DB_NAME") or "opslab",
                                user=c.get("DB_USER") or "app", password=c.get("DB_PASSWORD") or "", connect_timeout=3)
        try:
            with conn, conn.cursor() as cur:
                cur.execute("insert into notes(ct) values (%s)", (ct,))
                cur.execute("select ct, count(*) over () from notes order by id limit 1")
                old_ct, n = cur.fetchone()
        finally:
            conn.close()
        old = base64.b64decode(_vault("transit/decrypt/orders", {"ciphertext": old_ct})["plaintext"]).decode()
        return jsonify(status="ok", notes=n, new_key_version=ct.split(":")[1], oldest=old, oldest_key_version=old_ct.split(":")[1], **_base())
    except Exception as exc:  # noqa: BLE001
        return jsonify(status="error", message=str(exc).strip()[:300], **_base()), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("APP_PORT", "8080")))
