import CoreGraphics
import Foundation
import MoTouchPadCore

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

/// CGEvent 的可替换边界，动作序列可在测试中由记录型 sink 验证。
protocol MacInputSink: AnyObject {
    func moveNormalized(dx: Float, dy: Float, sensitivityPercent: Int)
    func click(button: PointerButton, count: Int)
    func beginPrimaryDrag()
    func dragNormalized(dx: Float, dy: Float, sensitivityPercent: Int)
    func endPrimaryDrag()
    func scroll(vertical: Int, horizontal: Int)
    func send(shortcut: KeyboardShortcut)
    func reset()
}
