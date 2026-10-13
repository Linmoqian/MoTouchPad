import AppKit
import Combine
import Foundation
import MoTouchPadCore
import SwiftUI

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

/// 用户本机的全局手势快捷键偏好；不写入网络协议，也不影响移动端设置。
@MainActor
final class GesturePreferences: ObservableObject {
    private static let storageKey = "MoTouchPad.gestureBindings.v1"
    private let defaults: UserDefaults

    @Published var bindings: GestureBindings {
        didSet { save() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let restored = try? JSONDecoder().decode(GestureBindings.self, from: data) {
            var migrated = restored
            // 新增动作在旧偏好中缺少键；显式清除的 null 仍保留。
            if let keys = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               keys["switchApp"] == nil {
                migrated.switchApp = GestureBindings.defaults.switchApp
            }
            bindings = migrated
        } else {
            bindings = .defaults
        }
    }

    func set(_ shortcut: KeyboardShortcut?, for command: GestureCommand) {
        bindings.set(shortcut, for: command)
    }

    func resetToDefaults() {
        bindings = .defaults
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(bindings),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if bindings.switchApp == nil { object["switchApp"] = NSNull() }
        guard let stored = try? JSONSerialization.data(withJSONObject: object) else { return }
        defaults.set(stored, forKey: Self.storageKey)
    }
}

struct GestureSettingsView: View {
    @ObservedObject var preferences: GesturePreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("手势快捷键")
                .font(.title2)
            Text("快捷键发送给当前前台 App；未设置的动作会被识别但不会注入。点击输入框后按下新的组合键，Delete 可清除。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("单指轻点后再次按住移动可拖移；四指轻点可切换应用。启用智能缩放后，双指右键等待 0.30 秒以区分双击。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Form {
                Section("浏览与缩放") {
                    rows(for: [.pageBack, .pageForward, .zoomIn, .zoomOut, .smartZoom])
                }
                Section("旋转与查询") {
                    rows(for: [.rotateClockwise, .rotateCounterClockwise, .lookUp])
                }
                Section("窗口与桌面") {
                    rows(for: [.missionControl, .appExpose, .spaceLeft, .spaceRight,
                               .showDesktop, .appLauncher, .switchApp])
                }
            }

            HStack {
                Spacer()
                Button("恢复默认快捷键") {
                    preferences.resetToDefaults()
                }
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 540)
    }

    @ViewBuilder
    private func rows(for commands: [GestureCommand]) -> some View {
        ForEach(commands) { command in
            HStack {
                Text(command.displayName)
                Spacer()
                ShortcutRecorder(value: shortcutBinding(for: command))
                    .frame(width: 170, height: 24)
                Button("清除") {
                    preferences.set(nil, for: command)
                }
                .disabled(preferences.bindings.binding(for: command) == nil)
            }
        }
    }

    private func shortcutBinding(for command: GestureCommand) -> Binding<KeyboardShortcut?> {
        Binding(
            get: { preferences.bindings.binding(for: command) },
            set: { preferences.set($0, for: command) })
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    @Binding var value: KeyboardShortcut?

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    func makeNSView(context: Context) -> ShortcutRecorderField {
        let field = ShortcutRecorderField()
        field.onShortcut = { shortcut in
            context.coordinator.value.wrappedValue = shortcut
        }
        return field
    }

    func updateNSView(_ field: ShortcutRecorderField, context: Context) {
        context.coordinator.value = $value
        field.stringValue = value?.displayName ?? "未设置"
        field.toolTip = "点按后按下组合键；Delete 清除"
    }

    final class Coordinator {
        var value: Binding<KeyboardShortcut?>

        init(value: Binding<KeyboardShortcut?>) {
            self.value = value
        }
    }
}

private final class ShortcutRecorderField: NSTextField {
    var onShortcut: ((KeyboardShortcut?) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEditable = false
        isSelectable = true
        isBezeled = true
        alignment = .center
        focusRingType = .default
        placeholderString = "未设置"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            onShortcut?(nil)
            return
        }
        let shortcut = KeyboardShortcut(event: event)
        guard shortcut.modifiers.rawValue != 0 || event.keyCode >= 96 else {
            NSSound.beep()
            return
        }
        onShortcut?(shortcut)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        keyDown(with: event)
        return true
    }
}

private extension GestureCommand {
    var displayName: String {
        switch self {
        case .pageBack: "双指右滑：上一页"
        case .pageForward: "双指左滑：下一页"
        case .zoomIn: "双指张开：放大"
        case .zoomOut: "双指捏合：缩小"
        case .rotateClockwise: "双指顺时针旋转"
        case .rotateCounterClockwise: "双指逆时针旋转"
        case .smartZoom: "双指双击：智能缩放"
        case .lookUp: "三指轻点：查词"
        case .missionControl: "四指上滑：调度中心"
        case .appExpose: "三指上滑／四指下滑：App Exposé"
        case .spaceLeft: "四指左滑：左侧空间"
        case .spaceRight: "四指右滑：右侧空间"
        case .showDesktop: "四指张开：显示桌面"
        case .appLauncher: "四指合拢：应用启动器"
        case .switchApp: "四指轻点：切换应用"
        }
    }
}
