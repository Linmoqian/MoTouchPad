import Foundation
import MoTouchPadCore
import Network

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

/// TCP 客户端：连接触控端，发送心跳并切分协议帧。
final class TouchClient {
    private let queue = DispatchQueue(label: "com.motouchpad.mac.client", qos: .userInteractive)
    private var connection: NWConnection?
    private var decoder = TouchFrameStreamDecoder()
    private var generation: UInt64 = 0
    private var isConnected = false

    private let deliveryGate = ConnectionDeliveryGate()
    var onFrames: (@MainActor ([TouchFrame]) -> Void)?
    var onStateChange: (@MainActor (Bool) -> Void)?
    var onError: (@MainActor (String) -> Void)?

    func connect(host: String, port: UInt16 = TouchProtocol.port) {
        queue.async { [weak self] in
            guard let self else { return }
            disconnectOnQueue(notify: false)
            let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedHost.isEmpty else {
                reportError("请输入触控端 IP 地址")
                return
            }

            generation &+= 1
            let token = generation
            deliveryGate.set(token)
            let tcp = NWProtocolTCP.Options()
            tcp.noDelay = true
            let newConnection = NWConnection(
                host: NWEndpoint.Host(trimmedHost),
                port: NWEndpoint.Port(rawValue: port)!,
                using: NWParameters(tls: nil, tcp: tcp))
            connection = newConnection
            decoder.reset()
            newConnection.stateUpdateHandler = { [weak self, weak newConnection] state in
                guard let newConnection else { return }
                self?.queue.async { [weak self, weak newConnection] in
                    guard let self, let newConnection else { return }
                    handle(state: state, connection: newConnection, token: token)
                }
            }
            newConnection.start(queue: queue)
        }
    }

    func disconnect() {
        queue.async { [weak self] in
            self?.disconnectOnQueue(notify: true)
        }
    }

    private func handle(state: NWConnection.State, connection current: NWConnection,
                        token: UInt64) {
        guard token == generation, connection === current else { return }
        switch state {
        case .ready:
            guard !isConnected else { return }
            isConnected = true
            deliver(token: token) { $0.onStateChange?(true) }
            startHeartbeat(connection: current, token: token)
            receive(connection: current, token: token)
        case .failed(let error):
            fail("连接失败：\(error)", connection: current, token: token)
        case .cancelled:
            disconnectOnQueue(notify: true)
        default:
            break
        }
    }

    private func startHeartbeat(connection current: NWConnection, token: UInt64) {
        queue.asyncAfter(deadline: .now() + 1) { [weak self, weak current] in
            guard let self, let current,
                  token == generation, connection === current, isConnected else { return }
            current.send(content: Data([TouchProtocol.heartbeat]),
                         completion: .contentProcessed { [weak self, weak current] error in
                guard let current else { return }
                self?.queue.async { [weak self, weak current] in
                    guard let self, let current,
                          token == generation, connection === current else { return }
                    if let error {
                        fail("心跳发送失败：\(error)", connection: current, token: token)
                    }
                }
            })
            startHeartbeat(connection: current, token: token)
        }
    }

    private func receive(connection current: NWConnection, token: UInt64) {
        guard token == generation, connection === current else { return }
        current.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) {
            [weak self, weak current] data, _, isComplete, error in
            guard let current else { return }
            self?.queue.async { [weak self, weak current] in
                guard let self, let current,
                      token == generation, connection === current else { return }
                if let data, !data.isEmpty {
                    if !ingest(data, token: token) {
                        fail("收到无法解析的触控帧", connection: current, token: token)
                        return
                    }
                }
                if isComplete || error != nil {
                    fail("触控端已断开", connection: current, token: token)
                    return
                }
                receive(connection: current, token: token)
            }
        }
    }

    private func ingest(_ data: Data, token: UInt64) -> Bool {
        do {
            let frames = try decoder.append(data)
            if !frames.isEmpty { deliver(token: token) { $0.onFrames?(frames) } }
        } catch {
            return false
        }
        return true
    }

    private func fail(_ message: String, connection current: NWConnection, token: UInt64) {
        guard token == generation, connection === current else { return }
        disconnectOnQueue(notify: true)
        reportError(message)
    }

    private func disconnectOnQueue(notify: Bool) {
        generation &+= 1
        deliveryGate.set(generation)
        connection?.cancel()
        connection = nil
        decoder.reset()
        if isConnected {
            isConnected = false
            if notify { deliver(token: generation) { $0.onStateChange?(false) } }
        }
    }

    private func reportError(_ message: String) {
        deliver(token: generation) { $0.onError?(message) }
    }

    private func deliver(token: UInt64, action: @escaping @MainActor (TouchClient) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.deliveryGate.matches(token) else { return }
            action(self)
        }
    }
}

/// 主线程消费前再次校验会话，阻止已解码但排队中的旧帧污染新连接。
private final class ConnectionDeliveryGate {
    private let lock = NSLock()
    private var token: UInt64 = 0
    func set(_ value: UInt64) {
        lock.lock()
        token = value
        lock.unlock()
    }
    func matches(_ value: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return token == value
    }
}
