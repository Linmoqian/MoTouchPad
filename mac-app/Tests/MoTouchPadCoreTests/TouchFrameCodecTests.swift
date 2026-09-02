import XCTest
@testable import MoTouchPadCore

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

final class TouchFrameCodecTests: XCTestCase {
    func testGoldenFramesRoundTrip() throws {
        for name in validFixtures where name != "stream-two-frames.hex" {
            let bytes = try fixture(named: name)
            let frame = try TouchFrameCodec.decode(bytes)
            XCTAssertEqual(TouchFrameCodec.encode(frame), bytes, name)
        }
    }

    func testInvalidFixturesAreRejected() throws {
        for name in invalidFixtures {
            XCTAssertThrowsError(try TouchFrameCodec.decode(fixture(named: name)), name)
        }
    }

    func testStreamParsing() throws {
        let source = try fixture(named: "stream-two-frames.hex")
        let chunks = [
            Data(source.prefix(1)),
            Data(source.dropFirst(1).prefix(6)),
            Data(source.dropFirst(7).prefix(24)),
            Data(source.dropFirst(31))
        ]
        var buffer = Data()
        var frames: [TouchFrame] = []
        for chunk in chunks {
            buffer.append(chunk)
            while let parsed = try TouchFrameCodec.parse(buffer) {
                frames.append(parsed.frame)
                buffer = Data(buffer.dropFirst(parsed.byteCount))
            }
        }

        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(frames.map { $0.type }, [.hello, .touch])
        XCTAssertEqual(frames.last?.contacts.count, 1)
    }

    func testWireSensitivityZeroMapsToOneHundred() throws {
        var bytes = try fixture(named: "empty-touch.hex")
        bytes[22] = 0
        XCTAssertEqual(try TouchFrameCodec.decode(bytes).sensitivityPercent, 100)
    }

    func testResetClearsPendingTap() throws {
        var clicks = 0
        let gestures = GestureRecognizer()
        gestures.onLeftClick = { clicks += 1 }
        gestures.feed(try TouchFrameCodec.decode(fixture(named: "single-down.hex")))
        gestures.reset()
        gestures.feed(try TouchFrameCodec.decode(fixture(named: "single-up.hex")))
        XCTAssertEqual(clicks, 0)
    }

    func testEmptySnapshotDoesNotClick() throws {
        var clicks = 0
        let gestures = GestureRecognizer()
        gestures.onLeftClick = { clicks += 1 }
        gestures.feed(try TouchFrameCodec.decode(fixture(named: "single-down.hex")))
        gestures.feed(try TouchFrameCodec.decode(fixture(named: "empty-touch.hex")))
        XCTAssertEqual(clicks, 0)
    }

    func testTwoFingerTapWaitsForExplicitRelease() {
        var clicks = 0
        let gestures = GestureRecognizer()
        gestures.onRightClick = { clicks += 1 }
        let touching = [
            TouchContact(id: 1, touching: true, x: 0.4, y: 0.5,
                         pressure: 0, major: 0, minor: 0),
            TouchContact(id: 2, touching: true, x: 0.6, y: 0.5,
                         pressure: 0, major: 0, minor: 0)
        ]
        let base = TouchFrame(
            type: .touch, sequence: 1, timestampNanos: 1,
            buttons: 0, sensitivityPercent: 100, naturalScrolling: false,
            contacts: touching)
        let empty = TouchFrame(
            type: .touch, sequence: 2, timestampNanos: 2,
            buttons: 0, sensitivityPercent: 100, naturalScrolling: false,
            contacts: [])
        let released = TouchFrame(
            type: .touch, sequence: 3, timestampNanos: 3,
            buttons: 0, sensitivityPercent: 100, naturalScrolling: false,
            contacts: touching.map {
                TouchContact(id: $0.id, touching: false, x: $0.x, y: $0.y,
                             pressure: $0.pressure, major: $0.major, minor: $0.minor)
            })

        gestures.feed(base)
        gestures.feed(empty)
        XCTAssertEqual(clicks, 0)
        gestures.feed(base)
        gestures.feed(released)
        XCTAssertEqual(clicks, 1)
    }

    private func fixture(named name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("protocol/fixtures/\(name)")
        let text = try String(contentsOf: url, encoding: .utf8)
        return Data(text.split(whereSeparator: { $0.isWhitespace }).map {
            UInt8($0, radix: 16)!
        })
    }

    private let validFixtures = [
        "hello-empty.hex",
        "empty-touch.hex",
        "single-down.hex",
        "single-move.hex",
        "single-up.hex",
        "two-scroll-start.hex",
        "two-scroll-move.hex",
        "two-pinch-start.hex",
        "two-pinch-move.hex",
        "five-finger-max.hex"
    ]

    private let invalidFixtures = [
        "invalid-version.hex",
        "invalid-type.hex",
        "invalid-count.hex",
        "invalid-float.hex",
        "invalid-length.hex",
        "invalid-flags.hex",
        "invalid-state.hex"
    ]
}
