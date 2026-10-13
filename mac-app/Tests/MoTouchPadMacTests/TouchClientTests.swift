import Foundation
import Network
import XCTest
import MoTouchPadCore
@testable import MoTouchPadMac

// Created on 2026-10-13.
// @author: https://github.com/Linmoqian

@MainActor
final class TouchClientTests: XCTestCase {
    func testRealTCPSplitAndCombinedFramesArriveInOrder() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        let ready = expectation(description: "listener ready")
        let received = expectation(description: "all frames received")
        let client = TouchClient()
        let expected = (1...50).map { number in
            TouchFrame(type: .touch, sequence: UInt32(number), timestampNanos: Int64(number),
                       sensitivityPercent: 100, naturalScrolling: false, contacts: [])
        }
        var actual: [TouchFrame] = []
        client.onFrames = { frames in
            actual += frames
            if actual.count == expected.count { received.fulfill() }
        }
        client.onError = { XCTFail($0) }
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
        }
        listener.newConnectionHandler = { connection in
            let bytes = expected.reduce(into: Data()) { $0.append(TouchFrameCodec.encode($1)) }
            connection.stateUpdateHandler = { state in
                if case .ready = state {
                    connection.send(content: bytes.prefix(7), completion: .contentProcessed { error in
                        XCTAssertNil(error)
                        connection.send(content: bytes.dropFirst(7), completion: .contentProcessed { error in
                            XCTAssertNil(error)
                        })
                    })
                }
                if case .cancelled = state { connection.stateUpdateHandler = nil }
            }
            connection.start(queue: .global(qos: .userInitiated))
            // Receive the client heartbeat so the accepted socket stays alive until cleanup.
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8) { _, _, _, _ in
                connection.cancel()
            }
        }
        listener.start(queue: .global(qos: .userInitiated))
        defer { client.disconnect(); listener.cancel() }
        await fulfillment(of: [ready], timeout: 3)
        guard let port = listener.port else { return XCTFail("missing listener port") }
        client.connect(host: "127.0.0.1", port: port.rawValue)
        await fulfillment(of: [received], timeout: 3)
        XCTAssertEqual(actual, expected)
        client.onError = nil
    }
}
