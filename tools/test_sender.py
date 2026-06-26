#!/usr/bin/env python3
# 測試用發送器：模擬 iPad 送封包，驗證 Windows 接收端。
# 在 Mac 或 PC 上都能跑。
#
# 用法:
#     python3 test_sender.py <Windows的IP>
#     (不給 IP 時預設打 127.0.0.1，方便在同一台機器先測)
#
# 它會依序「按下 -> 放開」每一個 bit。
# 打開記事本，把焦點放在記事本上，跑這支程式，就能看到字一個一個冒出來。

import socket
import struct
import sys
import time

PORT = 7777
ip = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
seq = 0


def send(mask: int):
    """送出一個封包：小端序的 (seq, mask)，與 C++ 端的 memcpy 對齊。"""
    global seq
    seq += 1
    pkt = struct.pack("<II", seq, mask)   # < = little-endian, II = 兩個 uint32
    sock.sendto(pkt, (ip, PORT))



print(f"目標 {ip}:{PORT}")
time.sleep(1)
for i in range(32):
    print(f"按下 bit {i}")
    send(1 << i)      # 只按住第 i 個鍵
    time.sleep(0.3)
    send(0)           # 全部放開
    time.sleep(0.1)

print("完成")
