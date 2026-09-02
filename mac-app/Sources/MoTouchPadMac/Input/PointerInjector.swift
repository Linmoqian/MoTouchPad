import AppKit
import CoreGraphics
import Foundation

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

/// macOS 桌面兼容输入层：把手势结果合成为 CGEvent。
enum PointerInjector {
    /// 归一化差分 → 当前鼠标所在屏幕的逻辑点位移。
    static func moveNormalized(dx: Float, dy: Float, sensitivityPercent: Int) {
        let location = CGEvent(source: nil)?.location ?? .zero
        let screen = NSScreen.screens.first { $0.frame.contains(location) } ?? NSScreen.main
        let size = screen?.frame.size ?? CGSize(width: 1, height: 1)
        move(dx: CGFloat(dx) * size.width,
             dy: CGFloat(dy) * size.height,
             sensitivityPercent: sensitivityPercent)
    }

    static func move(dx: CGFloat, dy: CGFloat, sensitivityPercent: Int) {
        let scale = CGFloat(sensitivityPercent) / 100
        guard dx != 0 || dy != 0 else { return }
        postMouseEvent(type: .mouseMoved, dx: dx * scale, dy: dy * scale)
    }

    static func leftClick() {
        postMouseEvent(type: .leftMouseDown)
        postMouseEvent(type: .leftMouseUp)
    }

    static func rightClick() {
        postMouseEvent(type: .rightMouseDown)
        postMouseEvent(type: .rightMouseUp)
    }

    static func scroll(wheelSteps: Int) {
        guard wheelSteps != 0 else { return }
        let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: Int32(clamping: wheelSteps),
            wheel2: 0,
            wheel3: 0)
        event?.post(tap: .cghidEventTap)
    }

    /// 捏合缩放 = 按住 Ctrl + 滚轮，与 Windows 兼容层保持一致。
    static func zoom(wheelSteps: Int) {
        guard wheelSteps != 0 else { return }
        let ctrlDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x3B, keyDown: true)
        ctrlDown?.flags = .maskControl
        ctrlDown?.post(tap: .cghidEventTap)
        scroll(wheelSteps: wheelSteps)
        let ctrlUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x3B, keyDown: false)
        ctrlUp?.flags = .maskControl
        ctrlUp?.post(tap: .cghidEventTap)
    }

    private static func postMouseEvent(type: CGEventType, dx: CGFloat = 0, dy: CGFloat = 0) {
        let location = CGEvent(source: nil)?.location ?? .zero
        let moved = CGPoint(x: location.x + dx, y: location.y + dy)
        let event = CGEvent(mouseEventSource: nil,
                            mouseType: type,
                            mouseCursorPosition: moved,
                            mouseButton: button(for: type))
        event?.post(tap: .cghidEventTap)
    }

    private static func button(for type: CGEventType) -> CGMouseButton {
        switch type {
        case .rightMouseDown, .rightMouseUp:
            return .right
        default:
            return .left
        }
    }
}
