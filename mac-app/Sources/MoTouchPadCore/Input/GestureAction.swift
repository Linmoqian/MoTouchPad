import Foundation

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

/// 手势核心输出的鼠标按键语义，不依赖任一桌面平台的事件 API。
public enum PointerButton: Equatable {
    case primary
    case secondary
}

/// 持续拖移的生命周期。
public enum DragPhase: Equatable {
    case began
    case moved
    case ended
}

/// 由 macOS 输入层绑定为用户可编辑快捷键的命令。
public enum GestureCommand: String, CaseIterable, Codable, Equatable, Identifiable {
    case pageBack
    case pageForward
    case zoomIn
    case zoomOut
    case rotateClockwise
    case rotateCounterClockwise
    case smartZoom
    case lookUp
    case missionControl
    case appExpose
    case spaceLeft
    case spaceRight
    case showDesktop
    case appLauncher
    case switchApp

    public var id: String { rawValue }
}

/// 从原始触控快照解释出的平台无关动作。
public enum GestureAction: Equatable {
    case move(dx: Float, dy: Float, sensitivityPercent: Int)
    case click(button: PointerButton, count: Int)
    case drag(phase: DragPhase, dx: Float, dy: Float, sensitivityPercent: Int)
    case scroll(vertical: Int, horizontal: Int)
    case command(GestureCommand, repeats: Int)
}
