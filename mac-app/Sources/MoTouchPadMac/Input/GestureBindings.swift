import AppKit
import CoreGraphics
import Foundation
import MoTouchPadCore

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

/// 可持久化的 macOS 键盘修饰键集合。
struct ShortcutModifiers: OptionSet, Codable, Equatable {
    let rawValue: UInt8

    static let command = ShortcutModifiers(rawValue: 1 << 0)
    static let control = ShortcutModifiers(rawValue: 1 << 1)
    static let option = ShortcutModifiers(rawValue: 1 << 2)
    static let shift = ShortcutModifiers(rawValue: 1 << 3)
    static let function = ShortcutModifiers(rawValue: 1 << 4)

    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UInt8.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var cgEventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.shift) { flags.insert(.maskShift) }
        if contains(.function) { flags.insert(.maskSecondaryFn) }
        return flags
    }

    init(event: NSEvent) {
        var value: ShortcutModifiers = []
        let flags = event.modifierFlags
        if flags.contains(.command) { value.insert(.command) }
        if flags.contains(.control) { value.insert(.control) }
        if flags.contains(.option) { value.insert(.option) }
        if flags.contains(.shift) { value.insert(.shift) }
        if flags.contains(.function) { value.insert(.function) }
        self = value
    }
}

/// 以硬件 key code 与修饰键保存的快捷键，避免受键盘布局文字影响。
struct KeyboardShortcut: Codable, Equatable {
    let keyCode: UInt16
    let modifiers: ShortcutModifiers

    init(keyCode: UInt16, modifiers: ShortcutModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(event: NSEvent) {
        self.init(keyCode: event.keyCode, modifiers: ShortcutModifiers(event: event))
    }

    var displayName: String {
        var names: [String] = []
        if modifiers.contains(.control) { names.append("⌃") }
        if modifiers.contains(.option) { names.append("⌥") }
        if modifiers.contains(.shift) { names.append("⇧") }
        if modifiers.contains(.command) { names.append("⌘") }
        if modifiers.contains(.function) { names.append("Fn") }
        names.append(Self.keyName(for: keyCode))
        return names.joined()
    }

    private static func keyName(for keyCode: UInt16) -> String {
        switch keyCode {
        case 0: "A"
        case 2: "D"
        case 48: "Tab"
        case 24: "="
        case 27: "-"
        case 30: "]"
        case 33: "["
        case 103: "F11"
        case 123: "←"
        case 124: "→"
        case 125: "↓"
        case 126: "↑"
        default: "键码 \(keyCode)"
        }
    }
}

/// macOS 端唯一的一套动作快捷键映射。nil 表示识别该手势但不注入按键。
struct GestureBindings: Codable, Equatable {
    var pageBack: KeyboardShortcut?
    var pageForward: KeyboardShortcut?
    var zoomIn: KeyboardShortcut?
    var zoomOut: KeyboardShortcut?
    var rotateClockwise: KeyboardShortcut?
    var rotateCounterClockwise: KeyboardShortcut?
    var smartZoom: KeyboardShortcut?
    var lookUp: KeyboardShortcut?
    var missionControl: KeyboardShortcut?
    var appExpose: KeyboardShortcut?
    var spaceLeft: KeyboardShortcut?
    var spaceRight: KeyboardShortcut?
    var showDesktop: KeyboardShortcut?
    var appLauncher: KeyboardShortcut?
    var switchApp: KeyboardShortcut? = KeyboardShortcut(keyCode: 48, modifiers: [.command])

    static let defaults = GestureBindings(
        pageBack: KeyboardShortcut(keyCode: 33, modifiers: [.command]),
        pageForward: KeyboardShortcut(keyCode: 30, modifiers: [.command]),
        zoomIn: KeyboardShortcut(keyCode: 24, modifiers: [.command]),
        zoomOut: KeyboardShortcut(keyCode: 27, modifiers: [.command]),
        rotateClockwise: nil,
        rotateCounterClockwise: nil,
        smartZoom: nil,
        lookUp: KeyboardShortcut(keyCode: 2, modifiers: [.control, .command]),
        missionControl: KeyboardShortcut(keyCode: 126, modifiers: [.control]),
        appExpose: KeyboardShortcut(keyCode: 125, modifiers: [.control]),
        spaceLeft: KeyboardShortcut(keyCode: 123, modifiers: [.control]),
        spaceRight: KeyboardShortcut(keyCode: 124, modifiers: [.control]),
        showDesktop: KeyboardShortcut(keyCode: 103, modifiers: [.function]),
        appLauncher: KeyboardShortcut(keyCode: 0, modifiers: [.function, .shift]))

    func binding(for command: GestureCommand) -> KeyboardShortcut? {
        switch command {
        case .pageBack: pageBack
        case .pageForward: pageForward
        case .zoomIn: zoomIn
        case .zoomOut: zoomOut
        case .rotateClockwise: rotateClockwise
        case .rotateCounterClockwise: rotateCounterClockwise
        case .smartZoom: smartZoom
        case .lookUp: lookUp
        case .missionControl: missionControl
        case .appExpose: appExpose
        case .spaceLeft: spaceLeft
        case .spaceRight: spaceRight
        case .showDesktop: showDesktop
        case .appLauncher: appLauncher
        case .switchApp: switchApp
        }
    }

    mutating func set(_ shortcut: KeyboardShortcut?, for command: GestureCommand) {
        switch command {
        case .pageBack: pageBack = shortcut
        case .pageForward: pageForward = shortcut
        case .zoomIn: zoomIn = shortcut
        case .zoomOut: zoomOut = shortcut
        case .rotateClockwise: rotateClockwise = shortcut
        case .rotateCounterClockwise: rotateCounterClockwise = shortcut
        case .smartZoom: smartZoom = shortcut
        case .lookUp: lookUp = shortcut
        case .missionControl: missionControl = shortcut
        case .appExpose: appExpose = shortcut
        case .spaceLeft: spaceLeft = shortcut
        case .spaceRight: spaceRight = shortcut
        case .showDesktop: showDesktop = shortcut
        case .appLauncher: appLauncher = shortcut
        case .switchApp: switchApp = shortcut
        }
    }
}
