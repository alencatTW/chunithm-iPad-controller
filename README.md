# Chunithm Touch — iPad 觸控鍵盤控制器

把 iPad 變成音樂遊戲《CHUNITHM》的觸控控制器，透過 WiFi 以低延遲 UDP 連線到 Windows PC，
將觸控狀態即時注入成鍵盤事件。

## 架構

```
 iPad (觸控偵測)  ──UDP──►  Windows (接收 + SendInput 注入)  ──►  遊戲
```

- **iPad 端**：全螢幕多點觸控，16 格 × 上下兩層 = 32 個觸控區，打包成 32-bit 狀態送出。（開發中）
- **Windows 端**：監聽 UDP，解析封包，把狀態變化注入成鍵盤事件。
- **傳輸**：UDP，傳「完整狀態」而非單一事件，掉包可自我修復。

## 設計重點

- **低延遲優先**：UDP 避開 TCP 的重傳與封包合併造成的延遲。
- **完整狀態 + 序號**：每個封包帶 32-bit 狀態與遞增序號，亂序/重複封包直接丟棄，掉包靠下一個封包自動修正。
- **批次注入**：同一封包內多鍵變化合併成單次 `SendInput`，更接近「同時按下」。
- **防卡鍵**：超過 300ms 收不到封包即放開所有鍵；程式關閉時也會清乾淨。
- 使用 scan code 注入，相容性較佳。

## 封包格式 (little-endian)

| 位移 | 型別 | 說明 |
|------|------|------|
| 0–3  | uint32 | seq：遞增序號 |
| 4–7  | uint32 | mask：每個 bit = 對應鍵是否按住 |

## 技術棧

C++ / Winsock / Win32 SendInput（Windows 端） · Swift / UIKit（iPad 端，開發中） · Python（測試工具）

## 編譯與執行（Windows）

```bash
# MSVC
cl /EHsc /O2 windows/chunithm_receiver.cpp ws2_32.lib
# 或 MinGW
g++ -O2 -o chunithm_receiver.exe windows/chunithm_receiver.cpp -lws2_32

# 測試（可在 Mac 或 PC 上跑）
python3 tools/test_sender.py <Windows的IP>
```
