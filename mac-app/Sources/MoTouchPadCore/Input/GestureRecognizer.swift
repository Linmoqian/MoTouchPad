import Foundation

// Created on 2026-09-02; updated 2026-10-13.
// @author: https://github.com/Linmoqian

/// 把移动端原始触控快照解释为平台无关的桌面动作。
///
/// 手势时长以发送端单调时间戳判断，延迟右键和静止停留用本机单调时钟安排。
public final class GestureRecognizer {
    public struct Config {
        public var tapMaxDuration: TimeInterval = 0.28
        public var tapMaxTravel: Float = 0.018
        public var pointerStartTravel: Float = 0.004
        public var smartZoomEnabled = true
        public var doubleTapMaxInterval: TimeInterval = 0.30
        public var doubleTapMaxDistance: Float = 0.03
        public var pinchTriggerRatio: Float = 0.10
        public var rotationTriggerRadians: Float = .pi / 18
        public var rotationStepRadians: Float = .pi / 12
        public var scrollLinesPerScreen: Float = 40
        public var pinchStepsPerScreen: Float = 24
        public var swipeMaxDuration: TimeInterval = 0.35
        public var swipeMinTravel: Float = 0.12
        public var swipeMinVelocity: Float = 0.35
        public var directionDominance: Float = 1.5
        public var threeFingerHoldDuration: TimeInterval = 0.12
        public var threeFingerHoldTravel: Float = 0.04

        public init() {}
    }

    public var config = Config()

    /// 若存在延迟中的双指右键，输入层据此安排一次本机计时器。
    public var pendingSecondaryTapDeadline: TimeInterval? {
        pendingSecondaryTap?.deadline
    }

    /// 协议 ID 范围 0...255，用固定四段位集代替每帧 Set 分配。
    private struct ContactIDs: Equatable {
        private var bits = SIMD4<UInt64>(repeating: 0)
        mutating func insert(_ id: UInt8) {
            bits[Int(id) / 64] |= UInt64(1) << (Int(id) % 64)
        }
        func contains(_ id: UInt8) -> Bool {
            bits[Int(id) / 64] & (UInt64(1) << (Int(id) % 64)) != 0
        }
        func isSubset(of other: ContactIDs) -> Bool {
            for index in 0..<4 where bits[index] & ~other.bits[index] != 0 { return false }
            return true
        }
    }

    private struct Snapshot {
        let ids: ContactIDs
        let orderedIDs: SIMD4<UInt8>
        let positions: SIMD8<Float>
        let count: Int
        let centroid: SIMD2<Float>
        let pairDistance: Float
        let pairAngle: Float
        let spread: Float
    }

    private struct BaseSession {
        var ids: ContactIDs
        let start: Snapshot
        var last: Snapshot
        let startedAt: TimeInterval
        var travel: Float
        var sawExplicitRelease: Bool
    }

    private struct SingleSession {
        var base: BaseSession
        var moved: Bool
        var sensitivityPercent: Int
        var secondTap = false
        var dragging = false
    }

    private enum TwoKind: Equatable {
        case undecided
        case scroll
        case horizontalScroll
        case pinch
        case rotate
        case consumed
    }

    private struct TwoSession {
        var base: BaseSession
        var kind: TwoKind
        var verticalRemainder: Float
        var horizontalRemainder: Float
        var pinchRemainder: Float
        var rotationRemainder: Float
        var matchesPendingSecondaryTap: Bool
    }

    private enum ThreeKind: Equatable {
        case pending
        case dragging
        case consumed
    }

    private struct ThreeSession {
        var base: BaseSession
        var kind: ThreeKind
        var sensitivityPercent: Int
        var holdDeadline: TimeInterval
    }

    private enum FourKind: Equatable {
        case pending
        case consumed
    }

    private struct FourSession {
        var base: BaseSession
        var kind: FourKind
    }

    private enum Mode {
        case idle
        case single(SingleSession)
        case two(TwoSession)
        case three(ThreeSession)
        case four(FourSession)
    }

    private struct PendingSecondaryTap {
        let centroid: SIMD2<Float>
        let deadline: TimeInterval
    }

    private var mode: Mode = .idle
    private var pendingSecondaryTap: PendingSecondaryTap?
    private var suppressUntilRelease = false
    private var lastPrimaryTap: (position: SIMD2<Float>, time: TimeInterval)?

    public var nextDeadline: TimeInterval? {
        let hold: TimeInterval?
        if case .three(let session) = mode, session.kind == .pending,
           session.base.travel <= config.tapMaxTravel {
            hold = session.holdDeadline
        } else {
            hold = nil
        }
        switch (pendingSecondaryTapDeadline, hold?.isFinite == true ? hold : nil) {
        case (let pending?, let hold?): return min(pending, hold)
        case (let pending?, nil): return pending
        case (nil, let hold?): return hold
        case (nil, nil): return nil
        }
    }

    /// Timer-driven gestures must also progress when the phone sends no stationary frames.
    public func advance(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> [GestureAction] {
        var actions = flushPending(now: now)
        if case .three(var session) = mode, session.kind == .pending,
           session.base.travel <= config.tapMaxTravel, now >= session.holdDeadline {
            session.kind = .dragging
            mode = .three(session)
            actions.append(.drag(phase: .began, dx: 0, dy: 0,
                                 sensitivityPercent: session.sensitivityPercent))
        }
        return actions
    }

    public init() {}

    /// 消费一帧原始快照。`now` 仅用于安排双指右键延迟，测试可传入确定时间。
    public func feed(_ frame: TouchFrame,
                     now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> [GestureAction] {
        guard frame.type == .touch else { return [] }

        var actions = flushPending(now: now)
        var active: [TouchContact] = []
        var released: [TouchContact] = []
        active.reserveCapacity(frame.contacts.count)
        for contact in frame.contacts {
            if contact.touching { active.append(contact) } else { released.append(contact) }
        }
        active.sort { $0.id < $1.id }

        if suppressUntilRelease {
            if active.isEmpty { suppressUntilRelease = false }
            return actions
        }

        guard active.count <= 4 else {
            actions += cancelAndSuppress()
            return actions
        }

        switch mode {
        case .idle:
            begin(active: active, frame: frame, now: now, actions: &actions)
        case .single(let single):
            feedSingle(single, active: active, released: released,
                       frame: frame, now: now, actions: &actions)
        case .two(let two):
            feedTwo(two, active: active, released: released,
                    frame: frame, now: now, actions: &actions)
        case .three(let three):
            feedThree(three, active: active, released: released,
                      frame: frame, now: now, actions: &actions)
        case .four(let four):
            feedFour(four, active: active, released: released,
                     frame: frame, now: now, actions: &actions)
        }
        return actions
    }

    /// 在没有新帧抵达时交付到期的双指右键。
    public func flushPending(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> [GestureAction] {
        guard let pending = pendingSecondaryTap, now >= pending.deadline else { return [] }
        pendingSecondaryTap = nil
        return [.click(button: .secondary, count: 1)]
    }

    /// 断连或用户主动断开时清理状态；若正拖移则显式释放左键。
    public func reset() -> [GestureAction] {
        var actions: [GestureAction] = []
        if case .three(let three) = mode, three.kind == .dragging {
            actions.append(.drag(phase: .ended, dx: 0, dy: 0,
                                 sensitivityPercent: three.sensitivityPercent))
        }
        if case .single(let single) = mode, single.dragging {
            actions.append(.drag(phase: .ended, dx: 0, dy: 0,
                                 sensitivityPercent: single.sensitivityPercent))
        }
        mode = .idle
        pendingSecondaryTap = nil
        suppressUntilRelease = false
        lastPrimaryTap = nil
        return actions
    }

    private func begin(active: [TouchContact], frame: TouchFrame, now: TimeInterval,
                       actions: inout [GestureAction]) {
        guard !active.isEmpty else { return }
        if active.count != 1 { lastPrimaryTap = nil }
        switch active.count {
        case 1:
            let current = base(for: active, frame: frame)
            let secondTap = lastPrimaryTap.map {
                sourceTime(frame) >= $0.time && sourceTime(frame) - $0.time <= config.doubleTapMaxInterval &&
                    distance($0.position, current.start.centroid) <= config.doubleTapMaxDistance
            } ?? false
            lastPrimaryTap = nil
            mode = .single(SingleSession(
                base: current, moved: false,
                sensitivityPercent: frame.sensitivityPercent, secondTap: secondTap))
        case 2:
            mode = .two(startTwo(active: active, frame: frame, now: now, actions: &actions))
        case 3:
            mode = .three(ThreeSession(
                base: base(for: active, frame: frame), kind: .pending,
                sensitivityPercent: frame.sensitivityPercent,
                holdDeadline: now + config.threeFingerHoldDuration))
        case 4:
            mode = .four(FourSession(base: base(for: active, frame: frame), kind: .pending))
        default:
            actions += cancelAndSuppress()
        }
    }

    private func startTwo(active: [TouchContact], frame: TouchFrame, now: TimeInterval,
                          actions: inout [GestureAction]) -> TwoSession {
        let snap = snapshot(for: active)
        let matchesPending = pendingSecondaryTap.map {
            now <= $0.deadline && distance($0.centroid, snap.centroid) <= config.doubleTapMaxDistance
        } ?? false
        if pendingSecondaryTap != nil, !matchesPending {
            actions += emitPendingSecondaryTap()
        }
        return TwoSession(
            base: BaseSession(ids: snap.ids, start: snap, last: snap,
                              startedAt: sourceTime(frame), travel: 0,
                              sawExplicitRelease: false),
            kind: .undecided,
            verticalRemainder: 0,
            horizontalRemainder: 0,
            pinchRemainder: 0,
            rotationRemainder: 0,
            matchesPendingSecondaryTap: matchesPending)
    }

    private func feedSingle(_ previous: SingleSession, active: [TouchContact],
                            released: [TouchContact], frame: TouchFrame,
                            now: TimeInterval, actions: inout [GestureAction]) {
        var session = previous
        if active.isEmpty {
            session.base.sawExplicitRelease = released.contains { session.base.ids.contains($0.id) }
            if session.dragging {
                actions.append(.drag(phase: .ended, dx: 0, dy: 0,
                                     sensitivityPercent: session.sensitivityPercent))
            } else if session.base.sawExplicitRelease,
               contactsStayedNearStart(released, start: session.base.start),
               elapsed(from: session.base, frame: frame) <= config.tapMaxDuration,
               session.base.travel <= config.tapMaxTravel,
               !session.moved {
                actions.append(.click(button: .primary, count: 1))
                lastPrimaryTap = (session.base.last.centroid, sourceTime(frame))
            }
            mode = .idle
            return
        }

        if active.count > 1 {
            if !session.moved {
                begin(active: active, frame: frame, now: now, actions: &actions)
            } else {
                actions += cancelAndSuppress()
            }
            return
        }

        let snap = snapshot(for: active)
        guard snap.ids == session.base.ids else {
            if !session.moved {
                mode = .single(SingleSession(
                    base: base(for: active, frame: frame), moved: false,
                    sensitivityPercent: frame.sensitivityPercent))
            } else {
                actions += cancelAndSuppress()
            }
            return
        }

        let delta = snap.centroid - session.base.last.centroid
        let total = snap.centroid - session.base.start.centroid
        session.base.travel += manhattan(delta)
        if session.moved || manhattan(total) > config.pointerStartTravel {
            // 首次跨阈值输出从触点按下以来的完整差分，避免丢掉积累位移。
            let movement = session.moved ? delta : total
            if session.secondTap {
                if !session.dragging {
                    actions.append(.drag(phase: .began, dx: 0, dy: 0,
                                         sensitivityPercent: frame.sensitivityPercent))
                    session.dragging = true
                }
                actions.append(.drag(phase: .moved, dx: movement.x, dy: movement.y,
                                     sensitivityPercent: frame.sensitivityPercent))
            } else {
                actions.append(.move(dx: movement.x, dy: movement.y,
                                     sensitivityPercent: frame.sensitivityPercent))
            }
            session.moved = true
        }
        session.base.last = snap
        session.sensitivityPercent = frame.sensitivityPercent
        mode = .single(session)
    }

    private func feedTwo(_ previous: TwoSession, active: [TouchContact],
                         released: [TouchContact], frame: TouchFrame,
                         now: TimeInterval, actions: inout [GestureAction]) {
        var session = previous
        if active.isEmpty {
            session.base.sawExplicitRelease = released.contains { session.base.ids.contains($0.id) }
            finishTwo(session, released: released, frame: frame, now: now, actions: &actions)
            return
        }

        let activeIds = identifiers(active)
        if active.count < 2, activeIds.isSubset(of: session.base.ids) {
            guard contactsStayedNearStart(active, start: session.base.start) else {
                actions += cancelAndSuppress()
                return
            }
            session.base.sawExplicitRelease = session.base.sawExplicitRelease ||
                released.contains { session.base.ids.contains($0.id) }
            if session.kind == .undecided {
                mode = .two(session)
            } else {
                actions += cancelAndSuppress()
            }
            return
        }

        if active.count != 2 || activeIds != session.base.ids {
            if active.count >= 3, active.count <= 4,
               session.kind == .undecided, session.base.travel <= config.tapMaxTravel {
                pendingSecondaryTap = nil
                begin(active: active, frame: frame, now: now, actions: &actions)
            } else {
                actions += cancelAndSuppress()
            }
            return
        }

        let snap = snapshot(for: active)
        let delta = snap.centroid - session.base.last.centroid
        let total = snap.centroid - session.base.start.centroid
        session.base.travel += manhattan(delta)
        let duration = elapsed(from: session.base, frame: frame)
        let velocity = session.base.travel / Float(max(duration, 0.001))

        if session.matchesPendingSecondaryTap, session.base.travel > config.tapMaxTravel {
            actions += emitPendingSecondaryTap()
            session.matchesPendingSecondaryTap = false
        }

        let previousKind = session.kind
        switch session.kind {
        case .undecided:
            let pinchRatio = session.base.start.pairDistance > 0
                ? abs(snap.pairDistance - session.base.start.pairDistance) / session.base.start.pairDistance
                : 0
            let angleTravel = abs(wrappedAngle(snap.pairAngle - session.base.start.pairAngle))
            if pinchRatio >= config.pinchTriggerRatio {
                session.kind = .pinch
            } else if angleTravel >= config.rotationTriggerRadians {
                session.kind = .rotate
            } else if isVertical(delta) && manhattan(total) >= 0.006 {
                session.kind = .scroll
            } else if manhattan(total) >= 0.006, isHorizontal(total),
                      duration <= config.swipeMaxDuration,
                      abs(total.x) >= config.swipeMinTravel,
                      velocity >= config.swipeMinVelocity {
                actions.append(.command(total.x > 0 ? .pageBack : .pageForward, repeats: 1))
                session.kind = .consumed
            } else if manhattan(total) >= 0.006, isHorizontal(total),
                      duration >= config.swipeMaxDuration || velocity < config.swipeMinVelocity {
                session.kind = .horizontalScroll
            }
        case .scroll, .horizontalScroll, .pinch, .rotate, .consumed:
            break
        }

        let reference = previousKind == .undecided ? session.base.start : session.base.last
        let gestureDelta = snap.centroid - reference.centroid
        switch session.kind {
        case .scroll:
            let signed = gestureDelta.y * config.scrollLinesPerScreen *
                (frame.naturalScrolling ? 1 : -1)
            session.verticalRemainder += signed
            let steps = integralSteps(&session.verticalRemainder)
            if steps != 0 { actions.append(.scroll(vertical: steps, horizontal: 0)) }
        case .horizontalScroll:
            let signed = gestureDelta.x * config.scrollLinesPerScreen *
                (frame.naturalScrolling ? 1 : -1)
            session.horizontalRemainder += signed
            let steps = integralSteps(&session.horizontalRemainder)
            if steps != 0 { actions.append(.scroll(vertical: 0, horizontal: steps)) }
        case .pinch:
            let denominator = max(reference.pairDistance, 0.001)
            session.pinchRemainder += (snap.pairDistance - reference.pairDistance) /
                denominator * config.pinchStepsPerScreen
            let steps = integralSteps(&session.pinchRemainder)
            if steps != 0 {
                actions.append(.command(steps > 0 ? .zoomIn : .zoomOut,
                                        repeats: abs(steps)))
            }
        case .rotate:
            session.rotationRemainder += wrappedAngle(snap.pairAngle - reference.pairAngle)
            let steps = Int((session.rotationRemainder / config.rotationStepRadians)
                .rounded(.towardZero))
            if steps != 0 {
                session.rotationRemainder -= Float(steps) * config.rotationStepRadians
                actions.append(.command(steps > 0 ? .rotateClockwise : .rotateCounterClockwise,
                                        repeats: abs(steps)))
            }
        case .undecided, .consumed:
            break
        }

        session.base.last = snap
        mode = .two(session)
    }

    private func finishTwo(_ session: TwoSession, released: [TouchContact], frame: TouchFrame,
                           now: TimeInterval, actions: inout [GestureAction]) {
        let isTap = session.base.sawExplicitRelease && session.kind == .undecided &&
            elapsed(from: session.base, frame: frame) <= config.tapMaxDuration &&
            session.base.travel <= config.tapMaxTravel &&
            contactsStayedNearStart(released, start: session.base.start)
        if isTap, session.matchesPendingSecondaryTap {
            pendingSecondaryTap = nil
            actions.append(.command(.smartZoom, repeats: 1))
        } else if isTap, !config.smartZoomEnabled {
            actions.append(.click(button: .secondary, count: 1))
        } else if isTap {
            pendingSecondaryTap = PendingSecondaryTap(
                centroid: session.base.start.centroid,
                deadline: now + config.doubleTapMaxInterval)
        } else if session.matchesPendingSecondaryTap {
            actions += emitPendingSecondaryTap()
        }
        mode = .idle
    }

    private func feedThree(_ previous: ThreeSession, active: [TouchContact],
                           released: [TouchContact], frame: TouchFrame,
                           now: TimeInterval, actions: inout [GestureAction]) {
        var session = previous
        if active.isEmpty {
            session.base.sawExplicitRelease = released.contains { session.base.ids.contains($0.id) }
            if session.kind == .pending,
               session.base.sawExplicitRelease,
               contactsStayedNearStart(released, start: session.base.start),
               elapsed(from: session.base, frame: frame) <= config.tapMaxDuration,
               session.base.travel <= config.tapMaxTravel {
                actions.append(.command(.lookUp, repeats: 1))
            } else if session.kind == .dragging {
                actions.append(.drag(phase: .ended, dx: 0, dy: 0,
                                     sensitivityPercent: session.sensitivityPercent))
            }
            mode = .idle
            return
        }

        let activeIds = identifiers(active)
        if active.count < 3, activeIds.isSubset(of: session.base.ids) {
            session.base.sawExplicitRelease = session.base.sawExplicitRelease ||
                released.contains { session.base.ids.contains($0.id) }
            if session.kind == .pending {
                guard contactsStayedNearStart(active, start: session.base.start) else {
                    actions += cancelAndSuppress()
                    return
                }
                // 部分 UP 后不再让停留计时器按下左键。
                session.holdDeadline = .infinity
                mode = .three(session)
            } else {
                actions += cancelAndSuppress()
            }
            return
        }

        if active.count != 3 || activeIds != session.base.ids {
            if active.count == 4, session.kind == .pending,
               session.base.travel <= config.tapMaxTravel {
                begin(active: active, frame: frame, now: now, actions: &actions)
            } else {
                actions += cancelAndSuppress()
            }
            return
        }

        let snap = snapshot(for: active)
        let delta = snap.centroid - session.base.last.centroid
        let total = snap.centroid - session.base.start.centroid
        session.base.travel += manhattan(delta)
        let duration = elapsed(from: session.base, frame: frame)
        let velocity = session.base.travel / Float(max(duration, 0.001))

        if session.kind == .pending {
            let quickUp = total.y <= -config.swipeMinTravel && isVertical(total) &&
                duration <= config.swipeMaxDuration && velocity >= config.swipeMinVelocity
            if quickUp {
                actions.append(.command(.appExpose, repeats: 1))
                session.kind = .consumed
            } else if !isUp(total), manhattan(total) > 0 {
                session.kind = .dragging
                actions.append(.drag(phase: .began, dx: 0, dy: 0,
                                     sensitivityPercent: frame.sensitivityPercent))
            } else if duration >= config.threeFingerHoldDuration,
                      session.base.travel <= config.threeFingerHoldTravel {
                session.kind = .dragging
                actions.append(.drag(phase: .began, dx: 0, dy: 0,
                                     sensitivityPercent: frame.sensitivityPercent))
            } else if duration >= config.swipeMaxDuration {
                session.kind = .dragging
                actions.append(.drag(phase: .began, dx: 0, dy: 0,
                                     sensitivityPercent: frame.sensitivityPercent))
            }
        }
        if session.kind == .dragging && (delta.x != 0 || delta.y != 0) {
            actions.append(.drag(phase: .moved, dx: delta.x, dy: delta.y,
                                 sensitivityPercent: frame.sensitivityPercent))
        }

        session.base.last = snap
        session.sensitivityPercent = frame.sensitivityPercent
        mode = .three(session)
    }

    private func feedFour(_ previous: FourSession, active: [TouchContact],
                          released: [TouchContact], frame: TouchFrame,
                          now _: TimeInterval, actions: inout [GestureAction]) {
        var session = previous
        if active.isEmpty {
            if session.kind == .pending,
               released.contains(where: { session.base.ids.contains($0.id) }),
               contactsStayedNearStart(released, start: session.base.start),
               elapsed(from: session.base, frame: frame) <= config.tapMaxDuration,
               session.base.travel <= config.tapMaxTravel {
                actions.append(.command(.switchApp, repeats: 1))
            }
            mode = .idle
            return
        }
        if active.count < 4, identifiers(active).isSubset(of: session.base.ids), session.kind == .pending {
            guard contactsStayedNearStart(active, start: session.base.start) else {
                actions += cancelAndSuppress()
                return
            }
            session.base.sawExplicitRelease = session.base.sawExplicitRelease ||
                released.contains { session.base.ids.contains($0.id) }
            mode = .four(session)
            return
        }
        guard active.count == 4, snapshot(for: active).ids == session.base.ids else {
            actions += cancelAndSuppress()
            return
        }

        let snap = snapshot(for: active)
        let total = snap.centroid - session.base.start.centroid
        let delta = snap.centroid - session.base.last.centroid
        session.base.travel += manhattan(delta)
        let duration = elapsed(from: session.base, frame: frame)
        let velocity = session.base.travel / Float(max(duration, 0.001))

        if session.kind == .pending {
            let spreadRatio = session.base.start.spread > 0
                ? (snap.spread - session.base.start.spread) / session.base.start.spread
                : 0
            if abs(spreadRatio) >= 0.20 {
                actions.append(.command(spreadRatio > 0 ? .showDesktop : .appLauncher,
                                        repeats: 1))
                session.kind = .consumed
            } else if duration <= config.swipeMaxDuration,
                      session.base.travel >= config.swipeMinTravel,
                      velocity >= config.swipeMinVelocity {
                if isVertical(total) {
                    actions.append(.command(total.y < 0 ? .missionControl : .appExpose,
                                            repeats: 1))
                    session.kind = .consumed
                } else if isHorizontal(total) {
                    actions.append(.command(total.x < 0 ? .spaceLeft : .spaceRight,
                                            repeats: 1))
                    session.kind = .consumed
                }
            } else if duration >= config.swipeMaxDuration {
                session.kind = .consumed
            }
        }
        session.base.last = snap
        mode = .four(session)
    }

    private func base(for active: [TouchContact], frame: TouchFrame) -> BaseSession {
        let snap = snapshot(for: active)
        return BaseSession(ids: snap.ids, start: snap, last: snap,
                           startedAt: sourceTime(frame), travel: 0,
                           sawExplicitRelease: false)
    }

    private func snapshot(for contacts: [TouchContact]) -> Snapshot {
        let count = Float(max(contacts.count, 1))
        var sum = SIMD2<Float>(repeating: 0)
        var ids = ContactIDs()
        var orderedIDs = SIMD4<UInt8>(repeating: 0)
        var positions = SIMD8<Float>(repeating: 0)
        for (index, contact) in contacts.enumerated() {
            ids.insert(contact.id)
            orderedIDs[index] = contact.id
            positions[index * 2] = contact.x
            positions[index * 2 + 1] = contact.y
            sum += SIMD2(contact.x, contact.y)
        }
        let centroid = sum / count
        let pairVector = contacts.count == 2
            ? SIMD2<Float>(contacts[1].x - contacts[0].x, contacts[1].y - contacts[0].y)
            : SIMD2<Float>(repeating: 0)
        let pairDistance = (pairVector.x * pairVector.x + pairVector.y * pairVector.y).squareRoot()
        let pairAngle = Float(atan2(Double(pairVector.y), Double(pairVector.x)))
        var spread: Float = 0
        if contacts.count == 4 {
            for contact in contacts { spread += distance(SIMD2(contact.x, contact.y), centroid) }
            spread /= count
        }
        return Snapshot(ids: ids, orderedIDs: orderedIDs, positions: positions,
                        count: contacts.count, centroid: centroid,
                        pairDistance: pairDistance, pairAngle: pairAngle, spread: spread)
    }

    private func sourceTime(_ frame: TouchFrame) -> TimeInterval {
        TimeInterval(frame.timestampNanos) / 1_000_000_000
    }

    private func elapsed(from session: BaseSession, frame: TouchFrame) -> TimeInterval {
        max(0, sourceTime(frame) - session.startedAt)
    }

    private func isVertical(_ delta: SIMD2<Float>) -> Bool {
        abs(delta.y) >= abs(delta.x) * config.directionDominance
    }

    private func isHorizontal(_ delta: SIMD2<Float>) -> Bool {
        abs(delta.x) >= abs(delta.y) * config.directionDominance
    }

    private func isUp(_ delta: SIMD2<Float>) -> Bool {
        delta.y < 0 && isVertical(delta)
    }

    private func integralSteps(_ remainder: inout Float) -> Int {
        // 二进制浮点在 0.1 × 40 这类理论整数附近会略小于整数，
        // 用极小容差避免向零截断丢掉一个滚动或缩放步进。
        let epsilon: Float = 0.0001
        let adjusted = remainder >= 0 ? remainder + epsilon : remainder - epsilon
        let steps = Int(adjusted.rounded(.towardZero))
        remainder -= Float(steps)
        if abs(remainder) < epsilon { remainder = 0 }
        return steps
    }

    private func wrappedAngle(_ angle: Float) -> Float {
        var value = angle
        while value > .pi { value -= .pi * 2 }
        while value < -.pi { value += .pi * 2 }
        return value
    }

    private func distance(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let delta = a - b
        return (delta.x * delta.x + delta.y * delta.y).squareRoot()
    }

    private func manhattan(_ vector: SIMD2<Float>) -> Float {
        abs(vector.x) + abs(vector.y)
    }

    private func emitPendingSecondaryTap() -> [GestureAction] {
        guard pendingSecondaryTap != nil else { return [] }
        pendingSecondaryTap = nil
        return [.click(button: .secondary, count: 1)]
    }

    private func cancelAndSuppress() -> [GestureAction] {
        let actions = reset()
        suppressUntilRelease = true
        return actions
    }

    private func identifiers(_ contacts: [TouchContact]) -> ContactIDs {
        var ids = ContactIDs()
        for contact in contacts { ids.insert(contact.id) }
        return ids
    }

    private func contactsStayedNearStart(_ contacts: [TouchContact], start: Snapshot) -> Bool {
        for contact in contacts {
            guard let index = (0..<start.count).first(where: { start.orderedIDs[$0] == contact.id }) else {
                return false
            }
            let travel = abs(contact.x - start.positions[index * 2]) +
                abs(contact.y - start.positions[index * 2 + 1])
            if travel > config.tapMaxTravel { return false }
        }
        return true
    }
}
