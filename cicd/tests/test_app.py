"""cicd 모듈 — 빌드 단계의 단위 시험(차단 기준). 코드가 기본 동작을 하는지만 본다(설정값은 보지 않는다)."""
import importlib.util
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
spec = importlib.util.spec_from_file_location("app", os.path.join(ROOT, "app", "app.py"))
mod = importlib.util.module_from_spec(spec)
sys.modules["app"] = mod
spec.loader.exec_module(mod)
client = mod.app.test_client()


def test_health():
    r = client.get("/health")
    assert r.status_code == 200


def test_api_ok_without_errors():
    os.environ["APP_ERROR_RATE"] = "0"
    for _ in range(5):
        assert client.get("/api").status_code == 200


def test_api_reports_version():
    os.environ["APP_VERSION"] = "t1"
    assert client.get("/api").get_json()["version"] == "t1"
