import Foundation

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

/// 把原始触控快照解释为桌面手势；真正的输入注入由平台 backend 完成。
public final class GestureRecognizer {
    public struct Config {
        public var tapMaxDuration: TimeInterval = 0.28
        public var tapMaxTravel: Float = 0.018
        public var pinchTriggerRatio: Float = 0.10
        public var scrollLinesPerScreen: Float = 40
        public var pinchWheelPerScreen: Float = 24

        public init() {}
    }

    public var config = Config()

    private enum Mode {
        case idle
        case single(anchor: UInt8, start: SIMD2<Float>, last: SIMD2<Float>,
                    startedAt: TimeInterval, travel: Float)
        case two(avg: SIMD2<Float>, distance: Float, startedAt: TimeInterval,
                 travel: Float, kind: TwoFingerKind)
    }

    private enum TwoFingerKind {
        case undecided
        case scroll
        case pinch
    }

    private var mode: Mode = .idle
    private var scrollRemainder: Float = 0
    private var pinchRemainder: Float = 0
    private var suppressUntilRelease = false

    public var onMove: ((Float, Float, Int) -> Void)?
    public var onScroll: ((Int, Bool) -> Void)?
    public var onZoom: ((Int) -> Void)?
    public var onLeftClick: (() -> Void)?
    public var onRightClick: (() -> Void)?

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    public init() {}

    public func reset() {
        mode = .idle
        scrollRemainder = 0
        pinchRemainder = 0
        suppressUntilRelease = false
    }

    public func feed(_ frame: TouchFrame) {
        guard frame.type == .touch else { return }
        let active = frame.contacts.filter { $0.touching }.sorted { $0.id < $1.id }
        let released = frame.contacts.filter { !$0.touching }
        if suppressUntilRelease {
            if active.isEmpty { suppressUntilRelease = false }
            return
        }
        if active.count > 2 {
            reset()
            suppressUntilRelease = true
            return
        }
        switch mode {
        case .idle:
            feedIdle(active)
        case .single(let anchor, let start, let last, let startedAt, let travel):
            feedSingle(active, anchor: anchor, start: start, last: last,
                       startedAt: startedAt, travel: travel,
                       sensitivityPercent: frame.sensitivityPercent,
                       released: released)
        case .two(let avg, let distance, let startedAt, let travel, let kind):
            feedTwo(active, avg: avg, distance: distance, startedAt: startedAt,
                    travel: travel, kind: kind, released: released,
                    naturalScrolling: frame.naturalScrolling)
        }
    }

    private func feedIdle(_ active: [TouchContact]) {
        guard let first = active.first else { return }
        if active.count == 1 {
            let position = position(first)
            mode = .single(anchor: first.id, start: position, last: position,
                           startedAt: now, travel: 0)
        } else {
            enterTwo(active)
        }
    }

    private func feedSingle(_ active: [TouchContact], anchor: UInt8,
                             start: SIMD2<Float>, last: SIMD2<Float>,
                             startedAt: TimeInterval, travel: Float,
                             sensitivityPercent: Int,
                             released: [TouchContact]) {
        guard active.count == 1,
              let contact = active.first(where: { $0.id == anchor }) else {
            if active.isEmpty,
               released.contains(where: { $0.id == anchor }),
               now - startedAt <= config.tapMaxDuration,
               travel <= config.tapMaxTravel {
                onLeftClick?()
            }
            mode = .idle
            if active.count >= 2 { enterTwo(active) }
            else if let contact = active.first {
                let position = position(contact)
                mode = .single(anchor: contact.id, start: position, last: position,
                               startedAt: now, travel: 0)
            }
            return
        }

        let current = position(contact)
        let delta = current - last
        let stepTravel = abs(delta.x) + abs(delta.y)
        let travelNow = travel + stepTravel
        if abs(current.x - start.x) + abs(current.y - start.y) > config.tapMaxTravel {
            onMove?(delta.x, delta.y, sensitivityPercent)
        }
        mode = .single(anchor: anchor, start: start, last: current,
                       startedAt: startedAt, travel: travelNow)
    }

    private func feedTwo(_ active: [TouchContact], avg: SIMD2<Float>,
                          distance: Float, startedAt: TimeInterval, travel: Float,
                          kind: TwoFingerKind, released: [TouchContact],
                          naturalScrolling: Bool) {
        guard active.count == 2 else {
            if active.isEmpty,
               !released.isEmpty,
               now - startedAt <= config.tapMaxDuration,
               travel <= config.tapMaxTravel,
               kind == .undecided {
                onRightClick?()
            }
            if active.isEmpty {
                scrollRemainder = 0
                pinchRemainder = 0
                mode = .idle
            } else {
                // One finger may have lifted while the other remains. Keep the
                // two-finger session until all contacts are released so the
                // remaining finger cannot become an accidental left click.
                mode = .two(avg: avg, distance: distance, startedAt: startedAt,
                            travel: travel, kind: kind)
            }
            return
        }

        let newAvg = (position(active[0]) + position(active[1])) * 0.5
        let newDistance = simdDistance(active[0], active[1])
        let avgDelta = newAvg - avg
        let travelNow = travel + abs(avgDelta.x) + abs(avgDelta.y)
        let distanceRatio = distance > 0 ? abs(newDistance - distance) / distance : 0

        var nextKind = kind
        if kind == .undecided, distanceRatio > config.pinchTriggerRatio {
            nextKind = .pinch
        } else if kind == .undecided,
                  abs(avgDelta.x) + abs(avgDelta.y) >= 0.006 {
            nextKind = .scroll
        }

        if nextKind == .pinch {
            mode = .two(avg: newAvg, distance: newDistance, startedAt: startedAt,
                        travel: travelNow, kind: nextKind)
            let ratio = distance > 0 ? (newDistance - distance) / distance : 0
            pinchRemainder += ratio * config.pinchWheelPerScreen
            let steps = Int(pinchRemainder.rounded(.towardZero))
            if steps != 0 {
                pinchRemainder -= Float(steps)
                onZoom?(steps)
            }
        } else if nextKind == .scroll {
            let signed = avgDelta.y * config.scrollLinesPerScreen *
                (naturalScrolling ? 1 : -1)
            scrollRemainder += signed
            let lines = Int(scrollRemainder.rounded(.towardZero))
            if lines != 0 {
                scrollRemainder -= Float(lines)
                onScroll?(lines, naturalScrolling)
            }
        }
        mode = .two(avg: newAvg, distance: newDistance, startedAt: startedAt,
                    travel: travelNow, kind: nextKind)
    }

    private func enterTwo(_ active: [TouchContact]) {
        scrollRemainder = 0
        pinchRemainder = 0
        let firstTwo = Array(active.prefix(2))
        let avg = (position(firstTwo[0]) + position(firstTwo[1])) * 0.5
        mode = .two(avg: avg, distance: simdDistance(firstTwo[0], firstTwo[1]),
                    startedAt: now, travel: 0, kind: .undecided)
    }

    private func position(_ contact: TouchContact) -> SIMD2<Float> {
        SIMD2(contact.x, contact.y)
    }

    private func simdDistance(_ a: TouchContact, _ b: TouchContact) -> Float {
        let d = position(a) - position(b)
        return (d.x * d.x + d.y * d.y).squareRoot()
    }
}
