"""partner sync batch (opslab net-3 장애 재현용) — 한 목적지로 TCP 연결을 많이 열어 두고, 닫히면 다시 연다.
사용: python3 pool.py <목적지 IP> <연결 수> [포트=80]
"""
import selectors, socket, sys, time

ip, want = sys.argv[1], int(sys.argv[2])
port = int(sys.argv[3]) if len(sys.argv) > 3 else 80
sel = selectors.DefaultSelector()
live, opened, last = 0, 0, 0.0

def open_one():
    global live, opened
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setblocking(False)
    try:
        s.connect_ex((ip, port))
    except OSError:
        s.close(); return False
    sel.register(s, selectors.EVENT_READ)
    live += 1; opened += 1
    return True

while True:
    budget, t0 = 3000, time.time()          # 초당 최대 3,000개씩 연다
    while live < want and budget > 0:
        if not open_one():
            break
        budget -= 1
    for key, _ in sel.select(timeout=0.3):   # 닫힘·실패는 읽기 가능 이벤트로 온다 → 정리 후 다시 연다
        s = key.fileobj
        try:
            data = s.recv(16)
        except OSError:
            data = b""
        if not data:
            sel.unregister(s); s.close(); live -= 1
    if time.time() - last > 10:
        print(f"pool {ip}:{port} live={live} opened_total={opened}", flush=True); last = time.time()
    dt = time.time() - t0
    if dt < 1 and live >= want:
        time.sleep(0.2)
