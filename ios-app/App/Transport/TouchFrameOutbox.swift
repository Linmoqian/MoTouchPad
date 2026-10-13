import Foundation

// Created on 2026-10-13.
// @author: https://github.com/Linmoqian

/// 有界环形队列：只替换连续同触点的运动帧，保留 hello、DOWN、UP、取消和设置变化。
struct TouchFrameOutbox {
    private var slots: [(frame: TouchFrame, anchor: TouchFrame?)?]
    private var head = 0
    private(set) var count = 0
    private var previous: TouchFrame?
    private(set) var coalescedCount = 0

    init(capacity: Int = 32) {
        precondition(capacity > 1)
        slots = Array(repeating: nil, count: capacity)
    }

    /// false 表示关键帧积压；调用方结束连接，避免丢 UP 或继续回放旧动作。
    mutating func offer(_ frame: TouchFrame) -> Bool {
        let replaceable = previous.map { sameMotionSession($0, frame) } ?? false
        if count > 0 {
            let tail = (head + count - 1) % slots.count
            if replaceable, let entry = slots[tail], let anchor = entry.anchor,
               movementContinues(anchor, entry.frame, frame) {
                slots[tail] = (frame, anchor)
                previous = frame
                coalescedCount += 1
                return true
            }
        }
        guard count < slots.count else { return false }
        slots[(head + count) % slots.count] = (frame, replaceable ? previous : nil)
        count += 1
        previous = frame
        return true
    }

    mutating func pop() -> TouchFrame? {
        guard count > 0 else { return nil }
        let frame = slots[head]?.frame
        slots[head] = nil
        head = (head + 1) % slots.count
        count -= 1
        return frame
    }

    mutating func reset() {
        for index in slots.indices { slots[index] = nil }
        head = 0
        count = 0
        previous = nil
        coalescedCount = 0
    }

    private func sameMotionSession(_ first: TouchFrame, _ second: TouchFrame) -> Bool {
        guard first.type == .touch, second.type == .touch,
              !first.contacts.isEmpty, first.contacts.count == second.contacts.count,
              first.buttons == second.buttons,
              first.sensitivityPercent == second.sensitivityPercent,
              first.naturalScrolling == second.naturalScrolling else { return false }
        for contact in first.contacts {
            guard contact.touching, second.contacts.contains(where: {
                $0.touching && $0.id == contact.id
            }) else { return false }
        }
        return true
    }

    // 保留方向反转与明显转弯，避免折返运动被压缩成“没移动”的轻点。
    private func movementContinues(_ anchor: TouchFrame, _ current: TouchFrame,
                                   _ next: TouchFrame) -> Bool {
        for point in current.contacts {
            guard let start = anchor.contacts.first(where: { $0.id == point.id }),
                  let end = next.contacts.first(where: { $0.id == point.id }) else { return false }
            let ax = point.x - start.x, ay = point.y - start.y
            let bx = end.x - point.x, by = end.y - point.y
            let dot = ax * bx + ay * by
            let magnitude = (ax * ax + ay * ay) * (bx * bx + by * by)
            if magnitude > 0 && (dot < 0 || dot * dot < 0.7225 * magnitude) { return false }
        }
        return true
    }
}
