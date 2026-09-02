import Foundation
import MoTouchPadCore

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

/// 将 Core 的语义动作转换为一个 macOS 输入 sink；快捷键未配置时静默。
final class GestureActionExecutor {
    private let sink: MacInputSink
    private var bindings: GestureBindings

    init(sink: MacInputSink = PointerInjector(), bindings: GestureBindings = .defaults) {
        self.sink = sink
        self.bindings = bindings
    }

    func updateBindings(_ bindings: GestureBindings) {
        self.bindings = bindings
    }

    func execute(_ actions: [GestureAction]) {
        for action in actions {
            switch action {
            case .move(let dx, let dy, let sensitivity):
                sink.moveNormalized(dx: dx, dy: dy, sensitivityPercent: sensitivity)
            case .click(let button, let count):
                sink.click(button: button, count: count)
            case .drag(let phase, let dx, let dy, let sensitivity):
                switch phase {
                case .began:
                    sink.beginPrimaryDrag()
                case .moved:
                    sink.dragNormalized(dx: dx, dy: dy, sensitivityPercent: sensitivity)
                case .ended:
                    sink.endPrimaryDrag()
                }
            case .scroll(let vertical, let horizontal):
                sink.scroll(vertical: vertical, horizontal: horizontal)
            case .command(let command, let repeats):
                guard let shortcut = bindings.binding(for: command) else { continue }
                for _ in 0..<min(max(repeats, 0), 8) {
                    sink.send(shortcut: shortcut)
                }
            }
        }
    }

    func reset() {
        sink.reset()
    }
}
