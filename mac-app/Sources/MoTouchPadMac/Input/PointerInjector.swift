import AppKit
import CoreGraphics
import Foundation
import MoTouchPadCore

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

/// macOS 桌面兼容输入层：把手势结果合成为 CGEvent。
final class PointerInjector: MacInputSink {
    private var primaryButtonDown = false

    /// 归一化差分 → 当前鼠标所在屏幕的逻辑点位移。
    func moveNormalized(dx: Float, dy: Float, sensitivityPercent: Int) {
        postNormalizedMouseEvent(type: .mouseMoved, dx: dx, dy: dy,
                                 sensitivityPercent: sensitivityPercent)
    }

    func click(button: PointerButton, count: Int) {
        let repetitions = min(max(count, 1), 2)
        for clickState in 1...repetitions {
            switch button {
            case .primary:
                postMouseEvent(type: .leftMouseDown, clickState: clickState)
                postMouseEvent(type: .leftMouseUp, clickState: clickState)
            case .secondary:
                postMouseEvent(type: .rightMouseDown, clickState: clickState)
                postMouseEvent(type: .rightMouseUp, clickState: clickState)
            }
        }
    }

    func beginPrimaryDrag() {
        guard !primaryButtonDown else { return }
        postMouseEvent(type: .leftMouseDown, clickState: 1)
        primaryButtonDown = true
    }

    func dragNormalized(dx: Float, dy: Float, sensitivityPercent: Int) {
        let type: CGEventType = primaryButtonDown ? .leftMouseDragged : .mouseMoved
        postNormalizedMouseEvent(type: type, dx: dx, dy: dy,
                                 sensitivityPercent: sensitivityPercent)
    }

    func endPrimaryDrag() {
        guard primaryButtonDown else { return }
        postMouseEvent(type: .leftMouseUp, clickState: 1)
        primaryButtonDown = false
    }

    func scroll(vertical: Int, horizontal: Int) {
        guard vertical != 0 || horizontal != 0 else { return }
        let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: Int32(clamping: vertical),
            wheel2: Int32(clamping: horizontal),
            wheel3: 0)
        event?.post(tap: .cghidEventTap)
    }

    func send(shortcut: KeyboardShortcut) {
        let flags = shortcut.modifiers.cgEventFlags
        let down = CGEvent(keyboardEventSource: nil,
                           virtualKey: CGKeyCode(shortcut.keyCode),
                           keyDown: true)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: nil,
                         virtualKey: CGKeyCode(shortcut.keyCode),
                         keyDown: false)
        up?.flags = flags
        up?.post(tap: .cghidEventTap)
    }

    func reset() {
        endPrimaryDrag()
    }

    private func postNormalizedMouseEvent(type: CGEventType, dx: Float, dy: Float,
                                          sensitivityPercent: Int) {
        let location = CGEvent(source: nil)?.location ?? .zero
        let screen = NSScreen.screens.first { $0.frame.contains(location) } ?? NSScreen.main
        let size = screen?.frame.size ?? CGSize(width: 1, height: 1)
        let scale = CGFloat(sensitivityPercent) / 100
        postMouseEvent(type: type,
                       dx: CGFloat(dx) * size.width * scale,
                       dy: CGFloat(dy) * size.height * scale,
                       clickState: 0)
    }

    private func postMouseEvent(type: CGEventType, dx: CGFloat = 0, dy: CGFloat = 0,
                                clickState: Int) {
        let location = CGEvent(source: nil)?.location ?? .zero
        let moved = CGPoint(x: location.x + dx, y: location.y + dy)
        let event = CGEvent(mouseEventSource: nil,
                            mouseType: type,
                            mouseCursorPosition: moved,
                            mouseButton: button(for: type))
        if clickState > 0 {
            event?.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
        }
        event?.post(tap: .cghidEventTap)
    }

    private func button(for type: CGEventType) -> CGMouseButton {
        switch type {
        case .rightMouseDown, .rightMouseUp:
            return .right
        default:
            return .left
        }
    }
}
