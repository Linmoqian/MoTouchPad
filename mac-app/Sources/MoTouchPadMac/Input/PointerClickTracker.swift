import Foundation

// Created on 2026-10-13.
// @author: https://github.com/Linmoqian

/// 连续独立轻点必须设置 CGEvent clickState，系统才会解释为双击。
struct PointerClickTracker {
    private var previous: (time: TimeInterval, x: Double, y: Double)?

    mutating func record(now: TimeInterval, x: Double, y: Double, interval: TimeInterval) -> Int {
        guard let last = previous, now >= last.time, now - last.time <= interval,
              abs(x - last.x) <= 4, abs(y - last.y) <= 4 else {
            previous = (now, x, y)
            return 1
        }
        previous = nil
        return 2
    }

    mutating func reset() { previous = nil }
}
