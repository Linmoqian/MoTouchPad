import SwiftUI
import UIKit

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

struct TouchpadView: View {
    @StateObject private var model = TouchpadModel()
    @State private var showingSettings = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TouchSurface(model: model).ignoresSafeArea()
            StatusIsland(model: model) {
                showingSettings = true
            }
                .padding(.top, 12)
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .sheet(isPresented: $showingSettings) {
            SettingsView(model: model)
                .presentationDetents([.medium])
        }
    }
}

private struct StatusIsland: View {
    @ObservedObject var model: TouchpadModel
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(model.isConnected ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(model.isConnected ? "已连接" : "等待电脑连接")
                .foregroundStyle(.white)
                .font(.headline)
            Spacer()
            Text(model.isConnected ? "Wi-Fi" : "TCP \(TouchProtocol.port)")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Button(action: onSettings) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
        .padding(.horizontal, 24)
        if let errorMessage = model.errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.horizontal, 24)
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var model: TouchpadModel

    var body: some View {
        NavigationStack {
            Form {
                Section("触控板设置") {
                    HStack {
                        Text("指针灵敏度")
                        Spacer()
                        Text("\(model.sensitivityPercent)%")
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(model.sensitivityPercent) },
                            set: { model.sensitivityPercent = Int($0.rounded()) }),
                        in: 50...200,
                        step: 1)
                    Toggle("自然滚动", isOn: $model.naturalScrolling)
                }
            }
            .navigationTitle("设置")
        }
    }
}

struct TouchSurface: UIViewRepresentable {
    @ObservedObject var model: TouchpadModel

    func makeUIView(context: Context) -> TouchSurfaceView {
        let view = TouchSurfaceView()
        view.model = model
        return view
    }

    func updateUIView(_ uiView: TouchSurfaceView, context: Context) {}
}

final class TouchSurfaceView: UIView {
    var model: TouchpadModel?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isMultipleTouchEnabled = true
        isUserInteractionEnabled = true
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        report(event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        report(event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        report(event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        model?.cancel()
    }

    private func report(_ event: UIEvent?) {
        guard let model, let touches = event?.allTouches else { return }
        model.report(touches: touches, in: self)
    }
}

@MainActor
final class TouchpadModel: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var errorMessage: String?
    @Published var sensitivityPercent = 100
    @Published var naturalScrolling = false

    private let server = TouchServer()
    private let sequencer = TouchFrameSequencer()
    /// 协议要求跨帧稳定 ID；UITouch 对象身份在一次触控生命周期内保持稳定。
    private var touchIds: [ObjectIdentifier: UInt8] = [:]
    private var nextTouchId: UInt8 = 0

    init() {
        server.onStateChange = { [weak self] connected in
            Task { @MainActor in self?.isConnected = connected }
        }
        server.onError = { [weak self] message in
            Task { @MainActor in self?.errorMessage = message }
        }
    }

    func start() {
        errorMessage = nil
        server.start()
    }

    func stop() {
        server.stop()
        isConnected = false
    }

    func report(touches: Set<UITouch>, in view: UIView) {
        let width = max(view.bounds.width, 1)
        let height = max(view.bounds.height, 1)
        let contacts = touches
            .sorted { ObjectIdentifier($0) < ObjectIdentifier($1) }
            .map { touch in
                let location = touch.location(in: view)
                return TouchContact(
                    id: stableId(for: touch),
                    touching: touch.phase != .ended && touch.phase != .cancelled,
                    x: Float(min(max(location.x / width, 0), 1)),
                    y: Float(min(max(location.y / height, 0), 1)),
                    pressure: Float(touch.force / max(touch.maximumPossibleForce, 0.0001)),
                    major: Float(touch.majorRadius / width),
                    minor: Float(touch.majorRadius / height))
            }
        server.send(sequencer.makeSnapshot(
            contacts: contacts,
            sensitivityPercent: sensitivityPercent,
            naturalScrolling: naturalScrolling))

        if contacts.contains(where: { !$0.touching }) {
            server.send(sequencer.makeSnapshot(
                contacts: contacts.filter(\.touching),
                sensitivityPercent: sensitivityPercent,
                naturalScrolling: naturalScrolling))
        }

        for touch in touches where touch.phase == .ended || touch.phase == .cancelled {
            touchIds.removeValue(forKey: ObjectIdentifier(touch))
        }
    }

    func cancel() {
        server.send(sequencer.makeSnapshot(
            contacts: [],
            sensitivityPercent: sensitivityPercent,
            naturalScrolling: naturalScrolling))
        touchIds.removeAll()
    }

    private func stableId(for touch: UITouch) -> UInt8 {
        let key = ObjectIdentifier(touch)
        if let existing = touchIds[key] { return existing }
        nextTouchId &+= 1
        if nextTouchId == 0 { nextTouchId = 1 }
        let assigned = nextTouchId
        touchIds[key] = assigned
        return assigned
    }
}
