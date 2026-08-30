import Foundation
import Network

enum ConnectionType {
    case none
    case wifi
    // TODO(protocol v1 不变): USB 走有线网络接口后单独识别。
}

/// TCP 47651 服务端：接受 PC 连接，推送触控快照帧。
/// 入站方向仅消费 PC 的 0x7F 心跳保活字节（读后丢弃），EOF 即判除断连。
final class TouchServer {
    private let queue = DispatchQueue(label: "com.motouchpad.ios.server")
    private var listener: NWListener?
    private var connection: NWConnection?

    /// 出站帧队列上限；快照语义允许丢旧保新。
    private let maxPendingFrames = 256
    private var pendingFrames: [Data] = []

    private(set) var isConnected = false
    private(set) var connectionType: ConnectionType = .none
    var onStateChange: (() -> Void)?

    func start() {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: parameters, on: NWEndpoint.Port(rawValue: TouchProtocol.port)!) else {
            return
        }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
    }

    func stop() {
        queue.async { [weak self] in
            self?.teardown()
            self?.listener?.cancel()
            self?.listener = nil
        }
    }

    var pendingFrameCount: Int { queue.sync { pendingFrames.count } }

    /// 编码并排队一个触控快照；队列满时丢最旧。
    func send(_ frame: TouchFrame) {
        queue.async { [weak self] in
            guard let self, self.isConnected else { return }
            let data = frame.encoded()
            if self.pendingFrames.count >= self.maxPendingFrames {
                self.pendingFrames.removeFirst()
            }
            self.pendingFrames.append(data)
            self.flush()
        }
    }

    private func accept(_ connection: NWConnection) {
        queue.async { [weak self] in
            guard let self else { return }
            self.connection?.cancel()
            self.connection = connection
            self.isConnected = true
            self.connectionType = .wifi
            self.onStateChange?()
            self.receiveHeartbeats(connection)
            self.flush()
        }
    }

    private func receiveHeartbeats(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if isComplete || error != nil {
                self.queue.async { self.teardown() }
                return
            }
            // 协议 v1：控制字节（0x7F 心跳）读后即弃。
            self.receiveHeartbeats(connection)
        }
    }

    private func flush() {
        guard let connection, !pendingFrames.isEmpty else { return }
        let data = pendingFrames.removeFirst()
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if error != nil {
                self.queue.async { self.teardown() }
            } else {
                self.queue.async { self.flush() }
            }
        })
    }

    private func teardown() {
        connection?.cancel()
        connection = nil
        pendingFrames.removeAll()
        if isConnected {
            isConnected = false
            connectionType = .none
            onStateChange?()
        }
    }
}
