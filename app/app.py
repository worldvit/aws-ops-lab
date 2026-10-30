"""SK오앤에스 AWS 인프라 운영 과정 — 샘플 앱 (Day 1~8 공통)

경로
  /health  헬스체크 (ALB 타깃 그룹이 사용)
  /api     일반 응답
  /db      DB 조회 (Day 3부터 사용)
  /slow    지연 응답 (?sec=N, 최대 30초)

환경변수 (/etc/app/app.env 에서 읽음)
  APP_PORT        수신 포트 (기본 8080)
  APP_VERSION     응답에 표시할 버전 문자열 (Day 6 배포 실습에서 사용)
  APP_ERROR_RATE  /api 가 500을 반환할 확률 0.0~1.0 (기본 0)
  DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD   Day 3 DB 접속정보
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
    return jsonify(status="ok", message="hello from skons-ops", **_base())


@app.route("/slow")
def slow():
    try:
        sec = min(max(float(request.args.get("sec", "1")), 0), 30)
    except ValueError:
        sec = 1
    time.sleep(sec)
    return jsonify(status="ok", slept_sec=sec, **_base())


@app.route("/db")
def db():
    host = os.environ.get("DB_HOST")
    if not host:
        return jsonify(status="not_configured", message="DB_HOST is not set (Day 3부터 사용)", **_base()), 503
    try:
        import psycopg2  # Day 3에서 설치

        conn = psycopg2.connect(
            host=host,
            port=int(os.environ.get("DB_PORT", "5432")),
            dbname=os.environ.get("DB_NAME", "skons"),
            user=os.environ.get("DB_USER", "app"),
            password=os.environ.get("DB_PASSWORD", ""),
            connect_timeout=3,
        )
        with conn, conn.cursor() as cur:
            cur.execute("select now(), pg_is_in_recovery()")
            now, in_recovery = cur.fetchone()
        conn.close()
        return jsonify(status="ok", db_time=str(now), db_reader=in_recovery, **_base())
    except Exception as exc:  # noqa: BLE001
        return jsonify(status="error", message=str(exc)[:200], **_base()), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("APP_PORT", "8080")))
