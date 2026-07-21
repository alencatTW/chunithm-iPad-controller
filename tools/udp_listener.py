#!/usr/bin/env python3
# udp_listener.py — 監聽 UDP，解碼 iPad 送來的封包，驗證用。
# 用法：python3 udp_listener.py
#
# 在模擬器上測試時，App 的 IP 欄位填 127.0.0.1 即可連到這支監聽器
# （模擬器本體就是 Mac，走 localhost）。
#
# 封包格式 (little-endian，須與 UDPSender.swift / windows/chunithm_receiver.cpp 一致):
#     bytes 0..3 : uint32 seq   遞增序號
#     bytes 4..7 : uint32 mask  每個 bit = 對應鍵是否按住

import socket
import struct

PORT = 7777
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(("0.0.0.0", PORT))
print(f"監聽 UDP {PORT}...")

last_seq = None
while True:
    data, addr = sock.recvfrom(1024)
    seq, mask = struct.unpack("<II", data[:8])  # 與 App 端 littleEndian 對齊
    dropped = "" if last_seq is None or seq == last_seq + 1 else f"  <- 掉包！跳過 {seq - last_seq - 1} 個"
    last_seq = seq
    bits = "".join("1" if mask & (1 << i) else "0" for i in range(31, -1, -1))
    print(f"from {addr[0]:15}  seq={seq:6}  mask={mask:08x}  {bits}{dropped}")
