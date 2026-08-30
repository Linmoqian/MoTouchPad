import Foundation
import Network

/// TCP 客户端：连接 Android/iOS 触控端 47651，按秒发送心跳，
/// 将入站字节流切成协议帧回调。
final class TouchClient {
    private let queue = DispatchQueue(label: "com.motouchpad.mac.client")
    private var connection: NWConnection?
    private var buffer = Data()

    var onFrame: ((TouchFrame) -> Void)?
    var onStateChange: ((Bool) -> Void)?

    private(set) var isConnected = false

    func connect(host: String) {
        disconnect()
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: TouchProtocol.port)!,
            using: .tcp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.isConnected = true
                self.onStateChange?(true)
                self.startHeartbeat()
                self.receive()
            case .failed, .cancelled:
                if self.isConnected {
                    self.isConnected = false
                    self.onStateChange?(false)
                }
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        queue.sync {
            buffer.removeAll()
        }
        if isConnected {
            isConnected = false
            onStateChange?(false)
        }
    }

    private func startHeartbeat() {
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, let connection = self.connection, self.isConnected else { return }
            connection.send(content: Data([TouchProtocol.heartbeat]), completion: .contentProcessed { _ in })
            self.startHeartbeat()
        }
    }

    private func receive() {
        guard let connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if isComplete || error != nil {
                self.isConnected = false
                self.onStateChange?(false)
                return
            }
            if let data {
                self.ingest(data)
            }
            self.receive()
        }
    }

    private func ingest(_ data: Data) {
        buffer.append(data)
        while let (frame, byteCount) = TouchFrame.parse(buffer) {
            buffer.removeFirst(byteCount)
            onFrame?(frame)
        }
        // 无效流时防积压：只保留最多一帧的尾部尝试。
        if buffer.count > TouchProtocol.headerSize + TouchProtocol.maxContacts * TouchProtocol.contactSize {
            buffer.removeAll()
        }
    }
}
