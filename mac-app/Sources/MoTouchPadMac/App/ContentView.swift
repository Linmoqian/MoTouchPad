import ApplicationServices
import MoTouchPadCore
import SwiftUI

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

struct ContentView: View {
    @StateObject private var model = ReceiverModel()
    @State private var showingGestureSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Circle()
                    .fill(model.isConnected ? .green : .orange)
                    .frame(width: 10, height: 10)
                Text(model.isConnected ? "触控端已连接" : "等待触控端连接")
                    .font(.headline)
                Spacer()
                Button("手势设置") {
                    showingGestureSettings = true
                }
            }

            HStack {
                TextField("触控端 IP 地址", text: $model.host)
                    .textFieldStyle(.roundedBorder)
                Button(model.isConnected ? "断开" : "连接") {
                    model.toggleConnection()
                }
            }

            GroupBox("最近收到的帧") {
                Text(model.lastFrameDescription)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !model.accessibilityGranted {
                Text("⚠️ 需要辅助功能权限才能移动鼠标：系统设置 → 隐私与安全性 → 辅助功能 → 打开 MoTouchPad\n重新打包后需重新授权；若已勾选仍无效，删除条目重新添加后重启本应用")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("测试鼠标注入（向右跳 2% 屏宽）") {
                    PointerInjector().moveNormalized(dx: 0.02, dy: 0, sensitivityPercent: 100)
                }
                Text("点击后鼠标跳动 = 权限正常；不动 = 权限失效")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Text("默认后端：CGEvent；支持单至四指原始触点手势")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .sheet(isPresented: $showingGestureSettings) {
            GestureSettingsView(preferences: model.gesturePreferences)
        }
        .onReceive(model.gesturePreferences.$bindings) { bindings in
            model.updateGestureBindings(bindings)
        }
    }
}

@MainActor
final class ReceiverModel: ObservableObject {
    @Published var host = ""
    @Published private(set) var isConnected = false
    @Published private(set) var lastFrameDescription = "暂无"
    @Published private(set) var errorMessage: String?
    @Published private(set) var accessibilityGranted = true

    let gesturePreferences = GesturePreferences()

    private let client = TouchClient()
    private let inputRouter = TouchFrameRouter()

    init() {
        inputRouter.updateBindings(gesturePreferences.bindings)
        client.onFrame = { [weak self] frame in
            Task { @MainActor in self?.handle(frame) }
        }
        client.onStateChange = { [weak self] connected in
            Task { @MainActor in
                self?.isConnected = connected
                if !connected { self?.inputRouter.reset() }
            }
        }
        client.onError = { [weak self] message in
            Task { @MainActor in self?.errorMessage = message }
        }
        checkAccessibility()
    }

    /// CGEvent 注入需要辅助功能授权；首次启动主动拉起系统引导。
    private func checkAccessibility() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        accessibilityGranted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    func toggleConnection() {
        errorMessage = nil
        if isConnected {
            client.disconnect()
        } else {
            client.connect(host: host)
        }
    }

    func updateGestureBindings(_ bindings: GestureBindings) {
        inputRouter.updateBindings(bindings)
    }

    private func handle(_ frame: TouchFrame) {
        if !accessibilityGranted {
            accessibilityGranted = AXIsProcessTrusted()
        }
        switch frame.type {
        case .hello:
            lastFrameDescription = "hello 序号 \(frame.sequence)"
        case .touch:
            lastFrameDescription = """
            touch 序号 \(frame.sequence) 点数 \(frame.contacts.count) \
            灵敏度 \(frame.sensitivityPercent)% 自然滚动 \(frame.naturalScrolling)
            """
            inputRouter.route(frame)
        }
    }
}
