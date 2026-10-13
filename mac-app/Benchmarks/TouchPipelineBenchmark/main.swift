import Foundation
import MoTouchPadCore

// Created on 2026-10-13.
// @author: https://github.com/Linmoqian

let frame = TouchFrame(type: .touch, sequence: 1, timestampNanos: 1,
                      sensitivityPercent: 100, naturalScrolling: true,
                      contacts: (0..<4).map {
    TouchContact(id: UInt8($0), touching: true, x: Float($0) * 0.1 + 0.2,
                 y: 0.5, pressure: 0, major: 0, minor: 0)
})
let bytes = TouchFrameCodec.encode(frame)
var batch = Data()
for _ in 0..<128 { batch.append(bytes) }
var checksum = 0

func measure(_ name: String, iterations: Int, body: () throws -> Void) rethrows {
    var samples: [Double] = []
    for _ in 0..<5 {
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations { try body() }
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        samples.append(Double(elapsed) / Double(iterations) / 1_000)
    }
    print("\(name): \(String(format: "%.3f", samples.sorted()[2])) us/iteration (median of 5)")
}

try measure("decode-four-contacts", iterations: 20_000) {
    checksum += try TouchFrameCodec.decode(bytes).contacts.count
}
let gestures = GestureRecognizer()
measure("recognize-four-contacts", iterations: 20_000) {
    checksum += gestures.feed(frame, now: 0).count
}
try measure("parse-128-frame-batch", iterations: 500) {
    var pending = batch
    while let parsed = try TouchFrameCodec.parse(pending) {
        checksum += parsed.frame.contacts.count
        pending = Data(pending.dropFirst(parsed.byteCount))
    }
}
try measure("stream-128-frame-batch", iterations: 500) {
    var decoder = TouchFrameStreamDecoder()
    checksum += try decoder.append(batch).reduce(0) { $0 + $1.contacts.count }
}
print("checksum: \(checksum)")
