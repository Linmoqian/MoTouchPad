import Foundation
import MoTouchPadCore
import CRustCore

enum Operation { case frame(Data), advance, flush, reset, smart(Bool) }
struct Step { let scenario: String; let now: Double; let operation: Operation }
enum Failure: Error { case message(String) }
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw Failure.message(message) }
}
func unhex(_ text: String) throws -> Data {
    let chars = Array(text.filter { !$0.isWhitespace })
    try require(chars.count % 2 == 0, "odd hex length")
    return try Data(stride(from: 0, to: chars.count, by: 2).map { i in
        guard let byte = UInt8(String(chars[i...i+1]), radix: 16) else { throw Failure.message("bad hex") }
        return byte
    })
}
func parse(_ text: String) throws -> [Step] {
    try text.split(separator: "\n").filter { !$0.hasPrefix("#") }.map { line in
        let f = line.split(separator: "\t").map(String.init)
        try require(f.count == 4, "invalid trace row")
        guard let now = Double(f[2]), now.isFinite else { throw Failure.message("bad clock") }
        let op: Operation
        switch f[1] {
        case "frame": op = .frame(try unhex(f[3]))
        case "advance": op = .advance
        case "flush": op = .flush
        case "reset": op = .reset
        case "smart": try require(f[3] == "0" || f[3] == "1", "bad smart flag"); op = .smart(f[3] == "1")
        default: throw Failure.message("unknown operation")
        }
        return Step(scenario: f[0], now: now, operation: op)
    }
}
func swiftRun(_ core: GestureRecognizer, _ step: Step) throws -> [GestureAction] {
    switch step.operation {
    case .frame(let bytes): return core.feed(try TouchFrameCodec.decode(bytes), now: step.now)
    case .advance: return core.advance(now: step.now)
    case .flush: return core.flushPending(now: step.now)
    case .reset: return core.reset()
    case .smart(let enabled): core.config.smartZoomEnabled = enabled; return []
    }
}
// Explicit IDs: do not depend on a Swift/Rust enum's memory layout or iteration order.
let commands: [GestureCommand] = [.pageBack, .pageForward, .zoomIn, .zoomOut,
    .rotateClockwise, .rotateCounterClockwise, .smartZoom, .lookUp, .missionControl,
    .appExpose, .spaceLeft, .spaceRight, .showDesktop, .appLauncher, .switchApp]
func raw(_ a: GestureAction) -> MTPAction {
    switch a {
    case .move(let x, let y, let sensitivity): return MTPAction(kind: 1, code: Int32(sensitivity), value: 0, x: x, y: y)
    case .click(let button, let count): return MTPAction(kind: 2, code: button == .primary ? 1 : 2, value: Int32(count), x: 0, y: 0)
    case .drag(let phase, let x, let y, let sensitivity): return MTPAction(kind: 3,
        code: phase == .began ? 0 : phase == .moved ? 1 : 2, value: Int32(sensitivity), x: x, y: y)
    case .scroll(let vertical, let horizontal): return MTPAction(kind: 4, code: Int32(vertical), value: Int32(horizontal), x: 0, y: 0)
    case .command(let command, let repeats): return MTPAction(kind: 5, code: Int32(commands.firstIndex(of: command)! + 1), value: Int32(repeats), x: 0, y: 0)
    }
}
func converted(_ a: MTPAction) -> GestureAction {
    switch a.kind {
    case 1: return .move(dx: a.x, dy: a.y, sensitivityPercent: Int(a.code))
    case 2: return .click(button: a.code == 1 ? .primary : .secondary, count: Int(a.value))
    case 3: return .drag(phase: a.code == 0 ? .began : a.code == 1 ? .moved : .ended,
                         dx: a.x, dy: a.y, sensitivityPercent: Int(a.value))
    case 4: return .scroll(vertical: Int(a.code), horizontal: Int(a.value))
    case 5: precondition((1...15).contains(a.code)); return .command(commands[Int(a.code)-1], repeats: Int(a.value))
    default: preconditionFailure("unknown ABI action")
    }
}
func contribution(_ a: MTPAction) -> UInt64 {
    UInt64(a.kind) &+ UInt64(bitPattern: Int64(a.code)) &+ UInt64(bitPattern: Int64(a.value))
}
func checksum(_ actions: [GestureAction]) -> UInt64 {
    actions.reduce(UInt64(actions.count)) { $0 &+ contribution(raw($1)) }
}
final class RustCore {
    let handle: OpaquePointer
    var arena = [MTPAction](repeating: MTPAction(), count: Int(MTP_MAX_ACTIONS))
    init() { handle = mtp_create()! }
    deinit { mtp_destroy(handle) }
    func run(_ step: Step) throws -> Int {
        let count: Int32 = arena.withUnsafeMutableBufferPointer { out in
            switch step.operation {
            case .frame(let data): return data.withUnsafeBytes { bytes in
                mtp_feed(handle, bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count,
                         step.now, out.baseAddress, out.count)
            }
            case .advance: return mtp_advance(handle, step.now, out.baseAddress, out.count)
            case .flush: return mtp_flush(handle, step.now, out.baseAddress, out.count)
            case .reset: return mtp_reset(handle, out.baseAddress, out.count)
            case .smart(let enabled): return mtp_set_smart_zoom(handle, enabled ? 1 : 0)
            }
        }
        try require(count >= 0, "Rust returned \(count): \(step.scenario)")
        return Int(count)
    }
    var deadline: Double? {
        var time = 0.0; let present = mtp_deadline(handle, &time)
        precondition(present >= 0); return present == 1 ? time : nil
    }
    func materialize(_ count: Int) -> [GestureAction] { (0..<count).map { converted(arena[$0]) } }
    func checksum(_ count: Int) -> UInt64 { (0..<count).reduce(UInt64(count)) { $0 &+ contribution(arena[$1]) } }
}
struct Coverage: Codable { var steps = 0; var actions = 0; var commands: [String] = []; var kinds: [UInt32] = [] }
func compare(_ steps: [Step]) throws -> Coverage {
    let swift = GestureRecognizer(), rust = RustCore()
    var coverage = Coverage(), kinds = Set<UInt32>(), seenCommands = Set<String>()
    for (index, step) in steps.enumerated() {
        let expected = try swiftRun(swift, step), count = try rust.run(step)
        try require(count == expected.count, "action count \(step.scenario):\(index) Swift=\(expected) Rust=\(rust.materialize(count))")
        for (i, action) in expected.enumerated() {
            let a = raw(action), b = rust.arena[i]
            try require(a.kind == b.kind && a.code == b.code && a.value == b.value && abs(a.x-b.x) <= 0.000001 && abs(a.y-b.y) <= 0.000001,
                        "action mismatch \(step.scenario):\(index) Swift=\(action) Rust=\(converted(b))")
            kinds.insert(a.kind)
            if case .command(let command, _) = action { seenCommands.insert(command.rawValue) }
        }
        switch (swift.nextDeadline, rust.deadline) {
        case (nil, nil): break
        case (let a?, let b?): try require(abs(a-b) < 1e-9, "deadline mismatch \(step.scenario):\(index)")
        default: throw Failure.message("deadline presence mismatch \(step.scenario):\(index)")
        }
        try require(checksum(expected) == rust.checksum(count), "checksum mismatch")
        coverage.steps += 1; coverage.actions += count
    }
    coverage.kinds = kinds.sorted(); coverage.commands = seenCommands.sorted(); return coverage
}
// Reproducible adversarial trajectories: unique full-range IDs, shuffled order,
// mixed UP, upgrades, cancel, reset, timers, and values near recognition thresholds.
func stressSteps() -> [Step] {
    var seed: UInt64 = 0x4d545031
    func random() -> UInt64 { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return seed }
    func unit() -> Float { Float(random() >> 40) / Float(1 << 24) }
    var steps: [Step] = []
    for session in 0..<800 {
        let start = Double(session) * 2 + 1000, n = Int(random() % 5) + 1
        steps.append(Step(scenario: "stress-\(session)", now: start, operation: .reset))
        steps.append(Step(scenario: "stress-\(session)", now: start, operation: .smart(random() % 2 == 0)))
        let ids = (0..<n).map { UInt8((session * 31 + $0 * 49) % 256) }
        let centerX: Float = 0.3 + unit() * 0.3, centerY: Float = 0.3 + unit() * 0.3
        let variant = session % 12, dx = (unit() - 0.5) * 0.25, dy = (unit() - 0.5) * 0.25
        for j in 0..<25 {
            let t = Float(j) / 24, now = start + Double(j) / (session % 2 == 0 ? 120 : 40)
            let angle = variant == 3 ? t * (unit() > 0.5 ? 0.9 : -0.9) : 0
            let scale: Float = variant == 4 ? 1+t*0.6 : variant == 5 ? 1-t*0.6 : 1
            var contacts = ids.enumerated().map { i, id -> TouchContact in
                let offset = Float(i) * 0.04 - Float(n-1)*0.02
                let x = centerX + offset*scale*cos(angle) + (variant < 3 ? dx*t : 0)
                let y = centerY + offset*scale*sin(angle) + (variant < 3 ? dy*t : 0)
                return TouchContact(id: id, touching: j < 24, x: x, y: y, pressure: unit(), major: 0.02, minor: 0.01)
            }
            if variant == 6 && j >= 12 { contacts.removeLast() }
            if variant == 7 && j == 12 { contacts = [] }
            if variant == 8 && j >= 12 && n < 5 { contacts.append(TouchContact(id: UInt8((session*31+245)%256), touching: j < 24, x: centerX, y: centerY, pressure: 0.5, major: 0.02, minor: 0.01)) }
            if variant == 9 && j >= 12 { contacts[0].id &+= 1 }
            if variant == 10 && j >= 12 { contacts[0].touching = false }
            contacts.reverse()
            let f = TouchFrame(type: .touch, sequence: UInt32(steps.count), timestampNanos: Int64((now*1e9).rounded()),
                sensitivityPercent: session % 2 == 0 ? 50 : 200, naturalScrolling: session % 3 == 0, contacts: contacts)
            steps.append(Step(scenario: "stress-\(session)", now: now, operation: .frame(TouchFrameCodec.encode(f))))
            if j == 15 { steps.append(Step(scenario: "stress-\(session)", now: now, operation: .advance)) }
            if variant == 11 && j == 16 { steps.append(Step(scenario: "stress-\(session)", now: now, operation: .reset)) }
        }
        steps.append(Step(scenario: "stress-\(session)", now: start+1, operation: .flush))
    }
    return steps
}
func boundarySteps() -> [Step] {
    var steps: [Step] = []
    for threshold: Float in [0.004, 0.006, 0.018, 0.03, 0.10, 0.12, 0.20, .pi/18, .pi/12] {
        for value in [threshold.nextDown, threshold, threshold.nextUp] {
            for n in 1...4 {
                let now = Double(steps.count) + 10_000, name = "boundary-\(n)-\(threshold)-\(value)"
                steps.append(Step(scenario: name, now: now, operation: .reset))
                for j in 0..<4 {
                    let angle: Float = threshold > 0.17 && n == 2 && j > 0 ? value : 0
                    let scale: Float = threshold == 0.10 || threshold == 0.20 ? (j > 0 ? 1+value : 1) : 1
                    let shift: Float = j > 0 && angle == 0 && scale == 1 ? value : (j == 2 ? 0.15 : 0)
                    let contacts = (0..<n).map { i in
                        let offset = Float(i)*0.08 - Float(n-1)*0.04
                        return TouchContact(id: UInt8(i*65), touching: j < 3,
                            x: 0.5+offset*scale*cos(angle), y: 0.5+offset*scale*sin(angle)+shift,
                            pressure: 0.5, major: 0.02, minor: 0.01)
                    }
                    let frame = TouchFrame(type: .touch, sequence: UInt32(steps.count),
                        timestampNanos: Int64(((now+Double(j)*0.04)*1e9).rounded()),
                        sensitivityPercent: 100, naturalScrolling: true, contacts: contacts)
                    steps.append(Step(scenario: name, now: now+Double(j)*0.04, operation: .frame(TouchFrameCodec.encode(frame))))
                }
            }
        }
    }
    return steps
}
func validateFixtures(_ root: URL) throws -> Int {
    let directory = root.appendingPathComponent("protocol/fixtures")
    let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("manifest.json"))) as! [String: Any]
    for file in manifest["valid"] as! [String] {
        let bytes = try unhex(String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8))
        var decoder = TouchFrameStreamDecoder()
        let frames = try decoder.append(bytes)
        try require(!frames.isEmpty && decoder.bufferedByteCount == 0, "fixture stream \(file)")
        for frame in frames {
            let wire = TouchFrameCodec.encode(frame)
            let step = Step(scenario: file, now: 1, operation: .frame(wire))
            _ = try compare([step, Step(scenario: file, now: 1, operation: .reset)])
        }
        for split in 0...bytes.count {
            var stream = TouchFrameStreamDecoder()
            let a = try stream.append(Data(bytes.prefix(split)))
            let b = try stream.append(Data(bytes.dropFirst(split)))
            try require(a+b == frames && stream.bufferedByteCount == 0, "fragment \(file):\(split)")
        }
    }
    for file in manifest["invalid"] as! [String] {
        let bytes = try unhex(String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8))
        do { _ = try TouchFrameCodec.decode(bytes); throw Failure.message("Swift accepted \(file)") }
        catch is TouchProtocolError {}
        let rust = RustCore()
        let code = rust.arena.withUnsafeMutableBufferPointer { out in bytes.withUnsafeBytes { b in
            mtp_feed(rust.handle, b.bindMemory(to: UInt8.self).baseAddress, b.count, 1, out.baseAddress, out.count)
        } }
        try require(code < 0, "Rust accepted \(file)")
    }
    return (manifest["valid"] as! [String]).count + (manifest["invalid"] as! [String]).count
}
struct Measurement: Codable {
    let path: String, steps: Int, samples: Int, repeats: Int
    let median_ns: Double, p95_block_ns: Double, p99_block_ns: Double
    let checksum: UInt64, blocks_ns: [Double]
}
func measure(_ path: String, steps: Int, repeats: Int, samples: Int, run: () throws -> UInt64) rethrows -> Measurement {
    var sum: UInt64 = 0, times: [Double] = []
    for _ in 0..<8 { sum &+= try run() }
    for _ in 0..<samples {
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<repeats { sum &+= try run() }
        times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / Double(steps*repeats))
    }
    let sorted = times.sorted()
    return Measurement(path: path, steps: steps, samples: samples, repeats: repeats,
        median_ns: sorted[samples/2], p95_block_ns: sorted[Int(ceil(Double(samples)*0.95))-1],
        p99_block_ns: sorted[Int(ceil(Double(samples)*0.99))-1], checksum: sum, blocks_ns: times)
}
struct Report: Codable { let coverage: Coverage, stress: Coverage, fixtures: Int, measurements: [Measurement] }
do {
    let args = CommandLine.arguments
    guard args.count >= 3 else { throw Failure.message("CompareCore ROOT OUTPUT [REPEATS] [SAMPLES]") }
    let root = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[2])
    let repeats = args.count > 3 ? Int(args[3])! : 32, samples = args.count > 4 ? Int(args[4])! : 51
    try require(repeats > 0 && samples > 0, "positive sample counts required")
    try require(mtp_abi_version() == 1 && mtp_action_size() == MemoryLayout<MTPAction>.stride, "ABI mismatch")
    try require(Float.pi.bitPattern == 0x40490fda, "Swift Float.pi representation changed; review Rust thresholds")
    let steps = try parse(String(contentsOf: root.appendingPathComponent("protocol/trajectories/gestures-v1.trace"), encoding: .utf8))
    let coverage = try compare(steps), stress = try compare(stressSteps() + boundarySteps()), fixtures = try validateFixtures(root)
    try require(coverage.commands == commands.map(\.rawValue).sorted() && coverage.kinds == [1,2,3,4,5], "incomplete gesture coverage")
    print("Parity passed: \(coverage.steps) shared steps, \(stress.steps) seeded steps, \(fixtures) fixtures; all 15 commands.")
    let swift = GestureRecognizer(), rustRaw = RustCore(), rustAdapted = RustCore()
    var measurements: [Measurement] = []
    measurements.append(try measure("swift-native", steps: steps.count, repeats: repeats, samples: samples) {
        var sum: UInt64 = 0; for step in steps {
            sum &+= checksum(try swiftRun(swift, step)); sum &+= swift.nextDeadline == nil ? 0 : 1
        }; return sum
    })
    measurements.append(try measure("swift-rust-raw", steps: steps.count, repeats: repeats, samples: samples) {
        var sum: UInt64 = 0; for step in steps {
            sum &+= rustRaw.checksum(try rustRaw.run(step)); sum &+= rustRaw.deadline == nil ? 0 : 1
        }; return sum
    })
    measurements.append(try measure("swift-rust-adapted", steps: steps.count, repeats: repeats, samples: samples) {
        var sum: UInt64 = 0; for step in steps {
            sum &+= checksum(rustAdapted.materialize(try rustAdapted.run(step))); sum &+= rustAdapted.deadline == nil ? 0 : 1
        }; return sum
    })
    try require(Set(measurements.map(\.checksum)).count == 1, "benchmark checksums differ")
    measurements.append(measure("c-abi-noop-loop", steps: 100_000, repeats: repeats, samples: samples) {
        var sum: UInt64 = 0; for i in 0..<100_000 { sum &+= mtp_noop(UInt64(i)) }; return sum
    })
    for m in measurements { print("\(m.path): median \(m.median_ns) ns/op, P95 block \(m.p95_block_ns), P99 block \(m.p99_block_ns)") }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(Report(coverage: coverage, stress: stress, fixtures: fixtures, measurements: measurements)).write(to: output)
} catch {
    FileHandle.standardError.write(Data("Comparison failed: \(error)\n".utf8)); exit(1)
}
