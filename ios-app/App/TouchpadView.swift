import SwiftUI
import UIKit

/// 触控主界面：全屏触控区域 + 顶部状态骨架。
/// 手势识别（滚动/捏合）由接收端完成，iOS 端只负责归一化快照上报。
struct TouchpadView: View {
    @StateObject private var model = TouchpadModel()

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TouchSurface(model: model).ignoresSafeArea()
            StatusIsland(model: model)
                .padding(.top, 12)
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}

private struct StatusIsland: View {
    @ObservedObject var model: TouchpadModel

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(model.isConnected ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(model.isConnected ? "已连接" : "等待电脑连接")
                .foregroundStyle(.white)
                .font(.headline)
            Spacer()
            Text(model.isConnected ? "Wi-Fi" : "TCP 47651")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
        .padding(.horizontal, 24)
    }
}

/// UIKit 触控桥接：SwiftUI 手势不足以表达任意指点数的多指追踪。
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
        report(event)
    }

    private func report(_ event: UIEvent?) {
        guard let model, let touches = event?.allTouches else { return }
        model.report(touches: touches, in: bounds)
    }
}

@MainActor
final class TouchpadModel: ObservableObject {
    @Published private(set) var isConnected = false
    @Published var sensitivityPercent = 100
    @Published var naturalScrolling = false

    private let server = TouchServer()
    private let sequencer = TouchFrameSequencer()
    /// 协议要求跨帧稳定 ID；UITouch 无稳定标识，按对象身份分配。
    private var touchIds: [ObjectIdentifier: UInt8] = [:]
    private var nextTouchId: UInt8 = 0

    init() {
        server.onStateChange = { [weak self] in
            self?.isConnected = self?.server.isConnected ?? false
        }
    }

    func start() { server.start() }
    func stop() { server.stop() }

    /// 把一组 UITouch 归一化为协议快照并交服务器排队。
    func report(touches: Set<UITouch>, in bounds: CGRect) {
        let width = max(bounds.width, 1)
        let height = max(bounds.height, 1)
        let contacts = touches.sorted { a, b in ObjectIdentifier(a) < ObjectIdentifier(b) }.map { touch in
            let location = touch.location(in: nil)
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
    }

    /// 为触点分配稳定 ID；ID 空间耗尽时重置字典重新分配。
    private func stableId(for touch: UITouch) -> UInt8 {
        let key = ObjectIdentifier(touch)
        if let existing = touchIds[key] { return existing }
        if touchIds.count >= Int(UInt8.max) { touchIds.removeAll() }
        nextTouchId &+= 1
        let assigned = nextTouchId
        touchIds[key] = assigned
        return assigned
    }
}
