import Foundation
import Network

// 負責透過 UDP 把觸控狀態送到 Windows PC。
// 封包格式 (小端序)，必須與 Windows 接收端一致:
//     bytes 0..3 : uint32 seq   每次遞增的序號
//     bytes 4..7 : uint32 mask  每個 bit = 對應的鍵是否按住
final class UDPSender {
    private var connection: NWConnection?
    private var seq: UInt32 = 0
    private let queue = DispatchQueue(label: "udp.sender")

    func connect(host: String, port: UInt16) {
        connection?.cancel()
        let nwHost = NWEndpoint.Host(host)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }

        let conn = NWConnection(host: nwHost, port: nwPort, using: .udp)
        conn.stateUpdateHandler = { state in
            print("UDP 連線狀態: \(state)")
        }
        conn.start(queue: queue)
        connection = conn
    }

    func send(mask: UInt32) {
        guard let conn = connection else { return }
        seq &+= 1                       // 溢位時自動繞回 (wrapping add)

        var s = seq.littleEndian        // 明確指定小端序，與 x86 Windows 對齊
        var m = mask.littleEndian
        var data = Data(capacity: 8)
        withUnsafeBytes(of: &s) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &m) { data.append(contentsOf: $0) }

        conn.send(content: data, completion: .idempotent)  // 射後不理，最低負擔
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
    }
}
