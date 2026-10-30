#!/bin/bash
# 부하 도구 — 부하 전용 EC2(<학번>-d1-loadgen)에서 Session Manager로 실행한다.
#
# 사용법
#   bash /opt/opslab/common/load.sh -u http://<ALB DNS> [-r 초당요청수] [-t 실행초] [-m 혼합비율]
#     -u  대상 URL (필수, 끝에 / 없이)
#     -r  초당 요청 수 (기본 20)
#     -t  실행 시간(초). 0이면 Ctrl+C 할 때까지 계속 (기본 0)
#     -m  경로 혼합 "경로:비율,경로:비율" (기본 "/api:95,/slow?sec=1:5")
#
# 10초마다 한 줄씩 요약을 출력하고, ~/load-<시각>.csv 에도 기록한다.
#   열: 시각, 요청수, 2xx, 4xx, 5xx, 연결오류, 평균ms, p95ms, 상태코드별 건수
set -euo pipefail

URL=""; RPS=20; DUR=0; MIX="/api:95,/slow?sec=1:5"
while getopts "u:r:t:m:" o; do
  case $o in
    u) URL=$OPTARG ;; r) RPS=$OPTARG ;; t) DUR=$OPTARG ;; m) MIX=$OPTARG ;;
    *) sed -n '2,12p' "$0"; exit 1 ;;
  esac
done
[ -z "$URL" ] && { sed -n '2,12p' "$0"; exit 1; }

exec python3 - "$URL" "$RPS" "$DUR" "$MIX" <<'PY'
import sys, time, random, threading, urllib.request, urllib.error, os, collections
from concurrent.futures import ThreadPoolExecutor

url, rps, dur, mix = sys.argv[1], float(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
paths, weights = [], []
for item in mix.split(","):
    p, w = item.rsplit(":", 1)
    paths.append(p); weights.append(float(w))

lock = threading.Lock()
win = {"lat": [], "codes": collections.Counter(), "err": 0}
logf = os.path.expanduser(time.strftime("~/load-%Y%m%d-%H%M%S.csv"))
with open(logf, "w") as f:
    f.write("time,requests,2xx,4xx,5xx,conn_err,avg_ms,p95_ms,codes\n")

def hit():
    path = random.choices(paths, weights)[0]
    t0 = time.time()
    code = None
    try:
        with urllib.request.urlopen(url + path, timeout=35) as r:
            r.read(); code = r.status
    except urllib.error.HTTPError as e:
        code = e.code
    except Exception:
        pass
    ms = (time.time() - t0) * 1000
    with lock:
        if code is None:
            win["err"] += 1
        else:
            win["codes"][code] += 1
            win["lat"].append(ms)

def report():
    while True:
        time.sleep(10)
        with lock:
            lat, codes, err = sorted(win["lat"]), win["codes"], win["err"]
            win["lat"], win["codes"], win["err"] = [], collections.Counter(), 0
        n = sum(codes.values()) + err
        c2 = sum(v for k, v in codes.items() if 200 <= k < 300)
        c4 = sum(v for k, v in codes.items() if 400 <= k < 500)
        c5 = sum(v for k, v in codes.items() if k >= 500)
        avg = sum(lat) / len(lat) if lat else 0
        p95 = lat[int(len(lat) * 0.95) - 1] if lat else 0
        detail = " ".join(f"{k}:{v}" for k, v in sorted(codes.items()))
        ts = time.strftime("%H:%M:%S")
        print(f"[{ts}] req={n:4d} 2xx={c2:4d} 4xx={c4:3d} 5xx={c5:3d} conn_err={err:3d} "
              f"avg={avg:6.0f}ms p95={p95:6.0f}ms  ({detail})", flush=True)
        with open(logf, "a") as f:
            f.write(f"{ts},{n},{c2},{c4},{c5},{err},{avg:.0f},{p95:.0f},{detail}\n")

print(f"target={url} rps={rps} mix={mix} log={logf}  (Ctrl+C로 중지)", flush=True)
threading.Thread(target=report, daemon=True).start()
pool = ThreadPoolExecutor(max_workers=200)
start = time.time(); interval = 1.0 / rps; nxt = start
try:
    while dur == 0 or time.time() - start < dur:
        pool.submit(hit)
        nxt += interval
        delay = nxt - time.time()
        if delay > 0:
            time.sleep(delay)
except KeyboardInterrupt:
    pass
print("stopped", flush=True)
os._exit(0)
PY
