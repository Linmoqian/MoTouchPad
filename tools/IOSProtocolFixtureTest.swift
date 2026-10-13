import Foundation

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

@main
struct IOSProtocolFixtureTest {
    static func main() throws {
        let fixtureRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("protocol/fixtures")

        for name in validFixtures where name != "stream-two-frames.hex" {
            let bytes = try readFixture(named: name, from: fixtureRoot)
            let frame = try TouchFrameCodec.decode(bytes)
            precondition(TouchFrameCodec.encode(frame) == bytes)
        }

        for name in invalidFixtures {
            let bytes = try readFixture(named: name, from: fixtureRoot)
            do {
                _ = try TouchFrameCodec.decode(bytes)
                fatalError("invalid fixture was accepted")
            } catch {
                // Expected protocol rejection.
            }
        }

        let stream = try readFixture(named: "stream-two-frames.hex", from: fixtureRoot)
        let frames = try split(stream).map { try TouchFrameCodec.decode($0) }
        precondition(frames.count == 2)
        precondition(frames[0].type == .hello && frames[1].type == .touch)
        precondition(frames[1].contacts.count == 1)

        var sensitivityZero = try readFixture(named: "empty-touch.hex", from: fixtureRoot)
        sensitivityZero[22] = 0
        let decodedSensitivityZero = try TouchFrameCodec.decode(sensitivityZero)
        precondition(decodedSensitivityZero.sensitivityPercent == 100)

        print("iOS codec validated " + String(validFixtures.count) + " valid and "
              + String(invalidFixtures.count) + " invalid fixtures.")
        try testOutbox(fixtureRoot)
    }

    private static func testOutbox(_ root: URL) throws {
        let down = try TouchFrameCodec.decode(readFixture(named: "single-down.hex", from: root))
        let up = try TouchFrameCodec.decode(readFixture(named: "single-up.hex", from: root))
        let cancel = try TouchFrameCodec.decode(readFixture(named: "empty-touch.hex", from: root))
        var outbox = TouchFrameOutbox()
        precondition(outbox.offer(down))
        for index in 1...1000 {
            var move = down
            move.sequence = UInt32(index)
            move.contacts[0].x = 0.3 + Float(index) * 0.0005
            precondition(outbox.offer(move))
        }
        precondition(outbox.count <= 3) // initial down and at most two movement segments
        precondition(outbox.offer(up))
        precondition(outbox.offer(cancel))
        precondition(outbox.pop() == down)
        var latest: TouchFrame?
        var drained: [TouchFrame] = []
        while let frame = outbox.pop() {
            drained.append(frame)
            if frame.contacts.first?.touching == true { latest = frame }
        }
        precondition(Array(drained.suffix(2)) == [up, cancel])
        precondition(latest?.sequence == 1000)
        precondition(outbox.count == 0)

        var bounded = TouchFrameOutbox(capacity: 2)
        precondition(bounded.offer(down))
        precondition(bounded.offer(up))
        precondition(!bounded.offer(cancel))
        precondition(bounded.pop() == down)
        precondition(bounded.pop() == up)
        bounded.reset()
        precondition(bounded.count == 0)

        var reversal = TouchFrameOutbox()
        var far = down
        far.contacts[0].x = 0.9
        precondition(reversal.offer(down))
        precondition(reversal.offer(far))
        precondition(reversal.offer(down))
        precondition(reversal.count == 3)
        print("iOS outbox: movement burst, release barriers, reversal, overflow and reset passed.")
    }

    private static func readFixture(named name: String, from root: URL) throws -> Data {
        let text = try String(
            contentsOf: root.appendingPathComponent(name),
            encoding: .utf8)
        return Data(text.split(whereSeparator: { $0.isWhitespace }).map {
            UInt8($0, radix: 16)!
        })
    }

    private static func split(_ data: Data) throws -> [Data] {
        var result: [Data] = []
        var offset = 0
        while offset < data.count {
            guard data.count - offset >= TouchProtocol.headerSize else {
                throw TouchProtocolError.truncated
            }
            let count = Int(data[offset + 20])
            guard count <= TouchProtocol.maxContacts else {
                throw TouchProtocolError.invalidContactCount(count)
            }
            let length = TouchProtocol.headerSize + count * TouchProtocol.contactSize
            guard data.count - offset >= length else {
                throw TouchProtocolError.truncated
            }
            result.append(Data(data[offset..<(offset + length)]))
            offset += length
        }
        return result
    }

    private static let validFixtures = [
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

    private static let invalidFixtures = [
        "invalid-version.hex",
        "invalid-type.hex",
        "invalid-count.hex",
        "invalid-float.hex",
        "invalid-length.hex",
        "invalid-flags.hex",
        "invalid-state.hex"
    ]
}
