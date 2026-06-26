#!/usr/bin/env python3
"""
延遲測試工具：量測 UDP 往返時間（RTT）。

兩種模式：
  server  — 在本機跑 echo 伺服器（不需要 Windows 端）
  client  — 打封包到目標並量測 RTT

用法：
  # 1. 先在同一台 Mac 或另一台機器開 echo server
  python3 latency_test.py server

  # 2. 打到本機 echo server 測網路路徑（同台機器）
  python3 latency_test.py client 127.0.0.1

  # 3. 打到真實 Windows receiver（需要 receiver 有回送支援，見 README）
  python3 latency_test.py client <Windows-IP>

  # 也可以直接不帶參數，預設 server mode
  python3 latency_test.py
"""

import socket
import struct
import sys
import time
import threading
import statistics

PORT        = 7778       # 用不同 port，不干擾正在跑的 receiver
ECHO_PORT   = 7778
N_PACKETS   = 200        # 量測封包數
INTERVAL_S  = 0.01      # 送包間隔：10 ms → 100 pps
TIMEOUT_S   = 0.5       # 等 echo 的逾時

# 封包格式：<II = seq(uint32) + timestamp_us(uint32, 取低32位)
PACK_FMT  = "<IQ"       # seq(u32) + timestamp_ns(u64)
PACK_SIZE = struct.calcsize(PACK_FMT)


# ── Server（echo 伺服器）─────────────────────────────────────────────────────

def run_server(host: str = "0.0.0.0", port: int = ECHO_PORT):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((host, port))
    print(f"[server] UDP echo 伺服器監聽 {host}:{port}  (Ctrl+C 停止)")
    received = 0
    try:
        while True:
            data, addr = sock.recvfrom(64)
            sock.sendto(data, addr)   # 原封不動送回
            received += 1
            if received % 50 == 0:
                print(f"[server] 已回送 {received} 個封包")
    except KeyboardInterrupt:
        print(f"\n[server] 結束，共回送 {received} 個封包")
    finally:
        sock.close()


# ── Client（發送並量測 RTT）──────────────────────────────────────────────────

def run_client(target_ip: str, port: int = ECHO_PORT,
               n: int = N_PACKETS, interval: float = INTERVAL_S):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(TIMEOUT_S)

    rtts: list[float] = []
    lost = 0

    print(f"[client] 目標 {target_ip}:{port}，發送 {n} 個封包，間隔 {interval*1000:.0f} ms")
    print(f"[client] 封包大小 {PACK_SIZE} bytes")
    print()

    for seq in range(1, n + 1):
        ts_send = time.perf_counter_ns()
        pkt = struct.pack(PACK_FMT, seq, ts_send)
        sock.sendto(pkt, (target_ip, port))

        try:
            data, _ = sock.recvfrom(64)
            ts_recv = time.perf_counter_ns()

            if len(data) >= PACK_SIZE:
                seq_r, ts_r = struct.unpack_from(PACK_FMT, data)
                if seq_r == seq:                 # 確認是同一個封包的回送
                    rtt_ms = (ts_recv - ts_send) / 1_000_000
                    rtts.append(rtt_ms)
                    if seq % 20 == 0 or seq <= 5:
                        print(f"  seq={seq:>4}  RTT={rtt_ms:.2f} ms")
        except socket.timeout:
            lost += 1
            print(f"  seq={seq:>4}  TIMEOUT (lost)")

        # 保持固定間隔（扣掉已花的時間）
        elapsed = (time.perf_counter_ns() - ts_send) / 1_000_000_000
        wait = interval - elapsed
        if wait > 0:
            time.sleep(wait)

    sock.close()

    # ── 統計摘要 ────────────────────────────────────────────────────────────
    print()
    print("=" * 48)
    print(f"  封包數量  : {n}")
    print(f"  丟包數量  : {lost}  ({lost/n*100:.1f}%)")

    if rtts:
        avg   = statistics.mean(rtts)
        med   = statistics.median(rtts)
        mn    = min(rtts)
        mx    = max(rtts)
        jtr   = statistics.stdev(rtts) if len(rtts) > 1 else 0.0
        p95   = sorted(rtts)[int(len(rtts) * 0.95)]
        p99   = sorted(rtts)[int(len(rtts) * 0.99)]

        print(f"  RTT min   : {mn:.2f} ms")
        print(f"  RTT avg   : {avg:.2f} ms")
        print(f"  RTT median: {med:.2f} ms")
        print(f"  RTT p95   : {p95:.2f} ms")
        print(f"  RTT p99   : {p99:.2f} ms")
        print(f"  RTT max   : {mx:.2f} ms")
        print(f"  Jitter    : {jtr:.2f} ms  (stdev)")
        print()
        print("  單向延遲估算 (RTT/2):")
        print(f"    平均 {avg/2:.2f} ms  ·  p95 {p95/2:.2f} ms  ·  max {mx/2:.2f} ms")
    else:
        print("  沒有收到任何回應，請確認 echo server 是否在線。")

    print("=" * 48)


# ── 入口 ─────────────────────────────────────────────────────────────────────

def main():
    args = sys.argv[1:]

    if not args or args[0] == "server":
        run_server()
    elif args[0] == "client":
        ip = args[1] if len(args) > 1 else "127.0.0.1"
        run_client(ip)
    else:
        # 只給 IP 也能跑（向下兼容）
        run_client(args[0])


if __name__ == "__main__":
    main()
