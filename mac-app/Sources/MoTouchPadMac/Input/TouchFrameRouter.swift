import MoTouchPadCore

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

/// macOS 应用的帧路由边界：网络解码后的快照只进入一个平台输入后端。
@MainActor
final class TouchFrameRouter {
    private let backend = CGEventInputBackend()

    func updateBindings(_ bindings: GestureBindings) {
        backend.updateBindings(bindings)
    }

    func route(_ frame: TouchFrame) {
        guard frame.type == .touch else { return }
        backend.submit(frame)
    }

    func reset() {
        backend.reset()
    }
}
