// chunithm_receiver.cpp
// iPad 觸控鍵盤 -> Windows 鍵盤注入 (UDP 接收端)
//
// 編譯 (在 Visual Studio 的 Developer Command Prompt 裡):
//     cl /EHsc /O2 chunithm_receiver.cpp ws2_32.lib
// 或在 Visual Studio 專案的 連結器 -> 輸入 加入 ws2_32.lib
//
// 封包格式 (小端序, little-endian)，iPad 端必須完全一致:
//     bytes 0..3 : uint32 seq   每次送遞增的序號 (用來丟棄亂序/重複封包)
//     bytes 4..7 : uint32 mask  每個 bit = 對應的鍵是否被按住

#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <cstdint>
#include <cstdio>
#include <cstring>

// #pragma comment(lib, "ws2_32.lib")

constexpr uint16_t LISTEN_PORT     = 7777;
constexpr int      RECV_TIMEOUT_MS = 300;  // 超過這麼久沒收到封包 -> 放開所有鍵 (防卡鍵)

// ---------------------------------------------------------------------------
// bit index -> scan code (Set 1)
// iPad 端必須使用「相同的 bit 順序」，這是兩端唯一要約定好的東西。
// 這裡：下層 16 格 = bit 0..15，上層 16 格 = bit 16..31。
// 下層已填入你給的 w s e d r f t g y h u j i k o l。
// 上層 16 鍵目前是佔位，請改成你實際綁定的鍵 (scan code 查表見下方註解)。
// ---------------------------------------------------------------------------
static const uint16_t kScan[32] = {
    // 下層 16 鍵:  w     s     e     d     r     f     t     g
    0x11, 0x1F, 0x12, 0x20, 0x13, 0x21, 0x14, 0x22,
    //             y     h     u     j     i     k     o     l
    0x15, 0x23, 0x16, 0x24, 0x17, 0x25, 0x18, 0x26,
    // 上層 16 鍵 (佔位: 1 2 3 4 5 6 7 8 9 0 - = [ ] ; ') —— 請依實際綁定修改
    0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
    0x0A, 0x0B, 0x0C, 0x0D, 0x1A, 0x1B, 0x27, 0x28,
};
// 常用 scan code 對照:
//   a=0x1E s=0x1F d=0x20 f=0x21 g=0x22 h=0x23 j=0x24 k=0x25 l=0x26
//   q=0x10 w=0x11 e=0x12 r=0x13 t=0x14 y=0x15 u=0x16 i=0x17 o=0x18 p=0x19
//   z=0x2C x=0x2D c=0x2E v=0x2F b=0x30 n=0x31 m=0x32

static uint32_t g_held = 0;  // 程式目前認為「按住」的鍵 bitmask

// 把目標狀態套用到鍵盤：只動「跟上次不同」的鍵，一次 SendInput 批次送出。
static void applyState(uint32_t newState) {
    uint32_t changed = g_held ^ newState;
    if (!changed) return;

    INPUT inputs[32];
    int n = 0;
    for (int i = 0; i < 32; ++i) {
        uint32_t bit = 1u << i;
        if (!(changed & bit)) continue;
        bool down = (newState & bit) != 0;

        INPUT& in = inputs[n++];
        in = {};
        in.type       = INPUT_KEYBOARD;
        in.ki.wScan   = kScan[i];
        in.ki.dwFlags = KEYEVENTF_SCANCODE | (down ? 0 : KEYEVENTF_KEYUP);
    }
    if (n > 0) SendInput(n, inputs, sizeof(INPUT));
    g_held = newState;
}

// 視窗被關 / Ctrl+C 時，確保不會留下卡住的按鍵。
static BOOL WINAPI consoleHandler(DWORD) {
    applyState(0);
    return FALSE;  // 交還給預設處理 (正常結束程式)
}

int main() {
    SetConsoleOutputCP(65001);
    SetConsoleCtrlHandler(consoleHandler, TRUE);

    WSADATA wsa;
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) {
        printf("WSAStartup 失敗\n");
        return 1;
    }

    SOCKET sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (sock == INVALID_SOCKET) {
        printf("建立 socket 失敗\n");
        return 1;
    }

    sockaddr_in addr{};
    addr.sin_family      = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;           // 接受任何網卡進來的封包
    addr.sin_port        = htons(LISTEN_PORT);
    if (bind(sock, (sockaddr*)&addr, sizeof(addr)) == SOCKET_ERROR) {
        printf("bind 失敗 (port %u 可能被占用)\n", LISTEN_PORT);
        return 1;
    }

    // 設定 recv 逾時：一段時間收不到封包就放開所有鍵。
    DWORD timeout = RECV_TIMEOUT_MS;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, (char*)&timeout, sizeof(timeout));

    // 拉高優先權，減少排程造成的延遲抖動。
    SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_TIME_CRITICAL);

    printf("聆聽 UDP port %u 中...  (Ctrl+C 結束)\n", LISTEN_PORT);

    uint32_t lastSeq  = 0;
    bool     haveSeq  = false;
    uint8_t  buf[64];

    for (;;) {
        sockaddr_in from{};
        int fromLen = sizeof(from);
        int len = recvfrom(sock, (char*)buf, sizeof(buf), 0,
                           (sockaddr*)&from, &fromLen);

        if (len == SOCKET_ERROR) {
            int e = WSAGetLastError();
            if (e == WSAETIMEDOUT) {
                // 一段時間沒訊號 -> 放開所有鍵，避免遊戲裡卡鍵。
                if (g_held) applyState(0);
                haveSeq = false;          // 下次無論序號為何都重新同步
                continue;
            }
            // 其他錯誤 (例如 WSAECONNRESET) 忽略後繼續。
            continue;
        }

        if (len < 8) continue;            // 封包太短，丟棄

        uint32_t seq, mask;
        memcpy(&seq,  buf,     4);
        memcpy(&mask, buf + 4, 4);

        // 丟棄亂序 / 重複的舊封包；用有號差值處理序號 wraparound。
        if (haveSeq && (int32_t)(seq - lastSeq) <= 0) continue;
        lastSeq = seq;
        haveSeq = true;

        applyState(mask);
    }

    // 程式不會正常走到這，保險起見:
    // closesocket(sock); WSACleanup();
}
