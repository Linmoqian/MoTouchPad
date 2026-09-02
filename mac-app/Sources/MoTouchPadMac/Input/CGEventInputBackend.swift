import MoTouchPadCore

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

/// macOS 的正式应用输入后端：手势由 Core 解释，动作由 CGEvent 注入。
final class CGEventInputBackend {
    private let gestures = GestureRecognizer()

    init() {
        gestures.onMove = { dx, dy, sensitivity in
            PointerInjector.moveNormalized(
                dx: dx,
                dy: dy,
                sensitivityPercent: sensitivity)
        }
        gestures.onScroll = { lines, _ in
            PointerInjector.scroll(wheelSteps: lines)
        }
        gestures.onZoom = { steps in
            PointerInjector.zoom(wheelSteps: steps)
        }
        gestures.onLeftClick = {
            PointerInjector.leftClick()
        }
        gestures.onRightClick = {
            PointerInjector.rightClick()
        }
    }

    func submit(_ frame: TouchFrame) {
        gestures.feed(frame)
    }

    func reset() {
        gestures.reset()
    }
}
