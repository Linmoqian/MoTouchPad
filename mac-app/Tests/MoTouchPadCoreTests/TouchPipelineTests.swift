import Foundation
import XCTest
@testable import MoTouchPadCore

// Created on 2026-10-13.
// @author: https://github.com/Linmoqian

final class TouchPipelineTests: XCTestCase {
    func testBatchDecoderHandlesEverySplitAndDataSlice() throws {
        let frames = [frame(0, 1), frame(100, 2), frame(200, 4)]
        let bytes = frames.reduce(into: Data()) { $0.append(TouchFrameCodec.encode($1)) }
        for split in 0...bytes.count {
            var decoder = TouchFrameStreamDecoder()
            let first = try decoder.append(Data(bytes.prefix(split)))
            let second = try decoder.append(Data(bytes.dropFirst(split)))
            XCTAssertEqual(first + second, frames, "split \(split)")
            XCTAssertEqual(decoder.bufferedByteCount, 0)
        }
        var padded = Data([0xFF])
        padded.append(TouchFrameCodec.encode(frames[0]))
        XCTAssertEqual(try TouchFrameCodec.decode(padded.dropFirst()), frames[0])
    }

    func testBatchDecoderRetainsPartialAndResetsOnError() throws {
        var decoder = TouchFrameStreamDecoder()
        let bytes = TouchFrameCodec.encode(frame(0, 1))
        XCTAssertTrue(try decoder.append(bytes.prefix(23)).isEmpty)
        XCTAssertEqual(decoder.bufferedByteCount, 23)
        XCTAssertEqual(try decoder.append(bytes.dropFirst(23)).count, 1)
        var invalid = bytes
        invalid[4] = 2
        XCTAssertThrowsError(try decoder.append(invalid.prefix(24)))
        XCTAssertEqual(decoder.bufferedByteCount, 0)
        XCTAssertEqual(try decoder.append(bytes).count, 1)
    }

    func testEarlyPointerMovementIncludesAccumulatedDeltaAndReversal() {
        let gestures = GestureRecognizer()
        _ = gestures.feed(frame(0, 1))
        var small = frame(10, 1)
        small.contacts[0].x += 0.002
        XCTAssertTrue(gestures.feed(small).isEmpty)
        small.contacts[0].x += 0.003
        let actions = gestures.feed(small)
        guard case .move(let dx, _, _) = actions.first else { return XCTFail("early move") }
        XCTAssertEqual(dx, 0.005, accuracy: 0.00001)
        guard case .move(let back, _, _) = gestures.feed(frame(20, 1)).first else {
            return XCTFail("pointer reversal")
        }
        XCTAssertEqual(back, -0.005, accuracy: 0.00001)
    }

    func testTapThenDragAndFiveFingerCancellationReleaseExactlyOnce() {
        let gestures = GestureRecognizer()
        _ = gestures.feed(frame(0, 1), now: 0)
        XCTAssertEqual(gestures.feed(frame(80, 1, up: true), now: 0.08), [.click(button: .primary, count: 1)])
        _ = gestures.feed(frame(150, 1), now: 0.15)
        var moved = frame(170, 1)
        moved.contacts[0].x += 0.02
        let actions = gestures.feed(moved, now: 0.17)
        XCTAssertEqual(actions.count, 2)
        XCTAssertEqual(actions.first, .drag(phase: .began, dx: 0, dy: 0, sensitivityPercent: 100))
        XCTAssertEqual(gestures.feed(frame(200, 5)), [.drag(phase: .ended, dx: 0, dy: 0, sensitivityPercent: 100)])
        XCTAssertTrue(gestures.reset().isEmpty)
    }

    func testStationaryThreeFingerTimerAndPartialReleaseCancelTimer() {
        let gestures = GestureRecognizer()
        _ = gestures.feed(frame(0, 3), now: 0)
        XCTAssertTrue(gestures.advance(now: 0.1).isEmpty)
        XCTAssertEqual(gestures.advance(now: 0.12), [.drag(phase: .began, dx: 0, dy: 0, sensitivityPercent: 100)])
        XCTAssertEqual(gestures.reset(), [.drag(phase: .ended, dx: 0, dy: 0, sensitivityPercent: 100)])
        _ = gestures.feed(frame(0, 3), now: 1)
        var partial = frame(20, 3)
        partial.contacts[0].touching = false
        XCTAssertTrue(gestures.feed(partial, now: 1.02).isEmpty)
        XCTAssertNil(gestures.nextDeadline)
        XCTAssertTrue(gestures.advance(now: 2).isEmpty)
    }

    func testPartialReleaseThenCancelDoesNotBecomeTap() {
        for count in 2...4 {
            let gestures = GestureRecognizer()
            _ = gestures.feed(frame(0, count), now: 0)
            var partial = frame(30, count)
            partial.contacts[0].touching = false
            _ = gestures.feed(partial, now: 0.03)
            XCTAssertTrue(gestures.feed(frame(50, 0), now: 0.05).isEmpty)
            XCTAssertTrue(gestures.advance(now: 1).isEmpty)
        }
    }

    func testPartialReleaseThenMovementDoesNotBecomeTap() {
        for count in 2...4 {
            let gestures = GestureRecognizer()
            _ = gestures.feed(frame(0, count), now: 0)
            var partial = frame(30, count)
            partial.contacts[0].touching = false
            _ = gestures.feed(partial, now: 0.03)
            partial.contacts.removeFirst()
            for index in partial.contacts.indices { partial.contacts[index].x += 0.2 }
            XCTAssertTrue(gestures.feed(partial, now: 0.06).isEmpty)
            for index in partial.contacts.indices { partial.contacts[index].touching = false }
            XCTAssertTrue(gestures.feed(partial, now: 0.08).isEmpty)
            XCTAssertTrue(gestures.advance(now: 1).isEmpty)
        }
    }

    func testReleaseCoordinatesAlsoPreventAccidentalClick() {
        for count in 1...4 {
            let gestures = GestureRecognizer()
            _ = gestures.feed(frame(0, count), now: 0)
            var released = frame(50, count, up: true)
            for index in released.contacts.indices { released.contacts[index].x += 0.2 }
            XCTAssertTrue(gestures.feed(released, now: 0.05).isEmpty)
            XCTAssertTrue(gestures.advance(now: 1).isEmpty)
        }
    }

    func testFourFingerTapAndHighContactIdentifiers() {
        let gestures = GestureRecognizer()
        var start = frame(0, 4)
        for index in start.contacts.indices { start.contacts[index].id = UInt8(index * 64 + 63) }
        _ = gestures.feed(start)
        start.timestampNanos = 50_000_000
        for index in start.contacts.indices { start.contacts[index].touching = false }
        XCTAssertEqual(gestures.feed(start), [.command(.switchApp, repeats: 1)])
    }

    func testUnboundSmartZoomDoesNotDelaySecondaryClick() {
        let gestures = GestureRecognizer()
        gestures.config.smartZoomEnabled = false
        _ = gestures.feed(frame(0, 2), now: 0)
        XCTAssertEqual(gestures.feed(frame(50, 2, up: true), now: 0.05),
                       [.click(button: .secondary, count: 1)])
        XCTAssertNil(gestures.nextDeadline)
    }

    func testGestureClassificationKeepsEarlierPinchTravel() {
        let gestures = GestureRecognizer()
        _ = gestures.feed(frame(0, 2))
        var step = frame(10, 2)
        step.contacts[0].x -= 0.002
        step.contacts[1].x += 0.002
        XCTAssertTrue(gestures.feed(step).isEmpty)
        step.contacts[0].x -= 0.004
        step.contacts[1].x += 0.004
        XCTAssertEqual(gestures.feed(step), [.command(.zoomIn, repeats: 3)])
    }

    private func frame(_ milliseconds: Int64, _ count: Int, up: Bool = false) -> TouchFrame {
        TouchFrame(type: .touch, sequence: UInt32(milliseconds), timestampNanos: milliseconds * 1_000_000,
                   sensitivityPercent: 100, naturalScrolling: true, contacts: (0..<count).map {
            TouchContact(id: UInt8($0), touching: !up, x: 0.3 + Float($0) * 0.08,
                         y: 0.5, pressure: 0, major: 0, minor: 0)
        })
    }
}
