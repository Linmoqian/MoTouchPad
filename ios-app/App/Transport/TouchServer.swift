import Foundation
import Network

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

enum ConnectionType: Equatable {
    case none
    case wifi
}

/// TCP 服务端：接受电脑连接，推送触控快照帧。
/// 入站方向只接受协议 v1 的 0x7F 心跳字节。
final class TouchServer {
    private let queue = DispatchQueue(label: "com.motouchpad.ios.server")
    private var listener: NWListener?
    private var connection: NWConnection?

    private let maxPendingFrames = 256
    private var pendingFrames: [Data] = []

    private(set) var isConnected = false
    private(set) var connectionType: ConnectionType = .none
    var onStateChange: ((Bool) -> Void)?
    var onError: ((String) -> Void)?

    func start() {
        queue.async { [weak self] in self?.startOnQueue() }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            teardown()
            listener?.cancel()
            listener = nil
        }
    }

    func send(_ frame: TouchFrame) {
        queue.async { [weak self] in
            guard let self, isConnected else { return }
            let data = TouchFrameCodec.encode(frame)
            enqueue(data)
            flush()
        }
    }

    private func startOnQueue() {
        guard listener == nil else { return }
        guard let port = NWEndpoint.Port(rawValue: TouchProtocol.port),
              let listener = try? NWListener(using: .tcp, on: port) else {
            reportError("无法监听 TCP (TouchProtocol.port)")
            return
        }
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            self?.queue.async { [weak self] in
                guard let self else { return }
                if case .failed(let error) = state {
                    reportError("TCP 监听失败：\(error)")
                    teardown()
                    listener.cancel()
                    self.listener = nil
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
    }

    private func accept(_ newConnection: NWConnection) {
        queue.async { [weak self] in
            guard let self else { return }
            teardown()
            connection = newConnection
            pendingFrames.removeAll()

            newConnection.stateUpdateHandler = { [weak self, weak newConnection] state in
                guard let newConnection else { return }
                self?.queue.async { [weak self, weak newConnection] in
                    guard let self, let newConnection, connection === newConnection else { return }
                    switch state {
                    case .ready:
                        isConnected = true
                        connectionType = .wifi
                        enqueueHello()
                        onStateChange?(true)
                        receiveHeartbeats(newConnection)
                        flush()
                    case .failed(let error):
                        reportError("TCP 连接失败：\(error)")
                        teardown(expected: newConnection)
                    case .cancelled:
                        teardown(expected: newConnection)
                    default:
                        break
                    }
                }
            }
            newConnection.start(queue: queue)
        }
    }

    private func receiveHeartbeats(_ current: NWConnection) {
        guard connection === current else { return }
        current.receive(minimumIncompleteLength: 1, maximumLength: 64) {
            [weak self, weak current] data, _, isComplete, error in
            guard let current else { return }
            self?.queue.async { [weak self, weak current] in
                guard let self, let current, connection === current else { return }
                if isComplete || error != nil {
                    teardown(expected: current)
                    return
                }
                if let data, data.contains(where: { $0 != TouchProtocol.heartbeat }) {
                    reportError("收到未知的控制字节")
                    teardown(expected: current)
                    return
                }
                receiveHeartbeats(current)
            }
        }
    }

    private func flush() {
        guard let current = connection, isConnected, !pendingFrames.isEmpty else { return }
        let data = pendingFrames.removeFirst()
        current.send(content: data, completion: .contentProcessed { [weak self, weak current] error in
            guard let current else { return }
            self?.queue.async { [weak self, weak current] in
                guard let self, let current, connection === current else { return }
                if let error {
                    reportError("触控帧发送失败：\(error)")
                    teardown(expected: current)
                } else {
                    flush()
                }
            }
        })
    }

    private func enqueueHello() {
        let hello = TouchFrame(
            type: .hello,
            sequence: 0,
            timestampNanos: 0,
            buttons: 0,
            contacts: [],
            sensitivityPercent: 100,
            naturalScrolling: false)
        enqueue(TouchFrameCodec.encode(hello))
    }

    private func enqueue(_ data: Data) {
        if pendingFrames.count >= maxPendingFrames {
            pendingFrames.removeFirst()
        }
        pendingFrames.append(data)
    }

    private func teardown(expected: NWConnection? = nil) {
        if let expected, connection !== expected { return }
        connection?.cancel()
        connection = nil
        pendingFrames.removeAll()
        if isConnected {
            isConnected = false
            connectionType = .none
            onStateChange?(false)
        }
    }

    private func reportError(_ message: String) {
        onError?(message)
    }
}
