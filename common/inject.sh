#!/bin/bash
# 장애 주입 도구 (수강생용) — CloudShell에서 실행한다.
#   bash ~/skons/common/inject.sh 1-1            Lab 1-1 장애 주입 (가설 수립을 끝낸 뒤)
#   bash ~/skons/common/inject.sh done 1-1       스스로 해결함 (verify.sh 통과 후)
#   bash ~/skons/common/inject.sh rollback 1-1   원복 (주입 후 40분 안에 해결하지 못했을 때)
#   bash ~/skons/common/inject.sh status         내 주입 기록 보기
#
# 장애의 원인과 변형은 이 스크립트에 들어 있지 않다. 강사 계정의 장애 주입 서비스가
# 내 계정의 skons-instructor-operator 역할을 맡아 무작위 변형 하나를 주입한다.
set -uo pipefail
: "${SID:?SID 환경변수에 학번을 넣으세요. 예) source ~/skons-env.sh}"
export AWS_REGION="${AWS_REGION:-ap-northeast-2}"

case "${1:-}" in
  [0-9]-[0-9]) ACTION=inject; LAB=$1 ;;
  done|rollback) ACTION=$1; LAB=${2:?"Lab 번호를 함께 적으세요. 예) $1 1-1"} ;;
  status) ACTION=status; LAB="" ;;
  *) sed -n '2,7p' "$0"; exit 1 ;;
esac

if [ "$ACTION" = rollback ]; then
  read -r -p "원복하면 이 Lab의 진단 기회가 끝납니다. 계속할까요? (y/N) " a; [ "$a" = y ] || exit 1
fi

URL="${SKONS_INJECTOR_URL:-$(grep -v '^#' "$(dirname "$0")/injector.url" 2>/dev/null | head -1)}"
[ -z "$URL" ] && { echo "장애 주입 서비스 주소가 없습니다. 강사에게 문의하세요 (common/injector.url)."; exit 2; }

python3 -c "import botocore" 2>/dev/null || pip3 install --user -q boto3

python3 - "$URL" "$ACTION" "$LAB" "$SID" "$AWS_REGION" <<'PY'
import json, sys, urllib.request, urllib.error
import botocore.session
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest

url, action, lab, sid, region = sys.argv[1:6]
body = json.dumps({"action": action, "lab": lab, "sid": sid})
creds = botocore.session.get_session().get_credentials().get_frozen_credentials()
req = AWSRequest(method="POST", url=url, data=body, headers={"content-type": "application/json"})
SigV4Auth(creds, "lambda", region).add_auth(req)
try:
    with urllib.request.urlopen(urllib.request.Request(url, data=body.encode(), headers=dict(req.headers), method="POST"), timeout=70) as r:
        out = json.loads(r.read())
except urllib.error.HTTPError as e:
    try:
        out = json.loads(e.read())
    except Exception:
        out = {"ok": False, "message": f"HTTP {e.code}"}

mark = "✅" if out.get("ok") else "❌"
if action == "status":
    print(f"{mark} {sid} 주입 기록")
    for r in sorted(out.get("records", []), key=lambda x: x["lab"]):
        print(f"  Lab {r['lab']}  {r['state']:<11} 주입 {r.get('injected_at') or '-'}  "
              f"해결 {r.get('resolved_at') or '-'}  원복 {r.get('rolled_back_at') or '-'}")
    if out.get("message"):
        print("  " + out["message"])
else:
    print(f"{mark} {out.get('message', '')}")
    if out.get("type"):
        print(f"   장애 유형: {out['type']}")
    if out.get("injected_at"):
        print(f"   주입 시각: {out['injected_at']}")
sys.exit(0 if out.get("ok") else 1)
PY
