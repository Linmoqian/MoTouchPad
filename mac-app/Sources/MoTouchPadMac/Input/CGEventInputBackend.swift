import Foundation
import MoTouchPadCore

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

/// macOS 正式输入后端：Core 解释手势，CGEvent 注入对应鼠标与快捷键。
@MainActor
final class CGEventInputBackend {
    private let gestures = GestureRecognizer()
    private let executor = GestureActionExecutor()
    private var pendingSecondaryTapWork: DispatchWorkItem?

    func updateBindings(_ bindings: GestureBindings) {
        if gestures.config.smartZoomEnabled != (bindings.smartZoom != nil) {
            reset()
        }
        gestures.config.smartZoomEnabled = bindings.smartZoom != nil
        executor.updateBindings(bindings)
    }

    func submit(_ frame: TouchFrame) {
        executor.execute(gestures.feed(frame))
        schedulePendingSecondaryTap()
    }

    func reset() {
        pendingSecondaryTapWork?.cancel()
        pendingSecondaryTapWork = nil
        executor.execute(gestures.reset())
        executor.reset()
    }

    private func schedulePendingSecondaryTap() {
        pendingSecondaryTapWork?.cancel()
        guard let deadline = gestures.nextDeadline else {
            pendingSecondaryTapWork = nil
            return
        }

        let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.executor.execute(self.gestures.advance())
            self.schedulePendingSecondaryTap()
        }
        pendingSecondaryTapWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
