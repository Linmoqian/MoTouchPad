import SwiftUI

struct ContentView: View {
    @StateObject private var model = ReceiverModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Circle()
                    .fill(model.isConnected ? .green : .orange)
                    .frame(width: 10, height: 10)
                Text(model.isConnected ? "触控端已连接" : "等待触控端连接")
                    .font(.headline)
                Spacer()
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

            Spacer()
            Text("骨架阶段：协议解码与指针注入已就绪，手势状态机待实现。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}

@MainActor
final class ReceiverModel: ObservableObject {
    @Published var host = ""
    @Published private(set) var isConnected = false
    @Published private(set) var lastFrameDescription = "暂无"

    private let client = TouchClient()

    init() {
        client.onFrame = { [weak self] frame in
            Task { @MainActor in self?.handle(frame) }
        }
        client.onStateChange = { [weak self] connected in
            Task { @MainActor in self?.isConnected = connected }
        }
    }

    func toggleConnection() {
        if isConnected {
            client.disconnect()
        } else {
            client.connect(host: host)
        }
    }

    private func handle(_ frame: TouchFrame) {
        switch frame.type {
        case .hello:
            lastFrameDescription = "hello 序号 \(frame.sequence)"
        case .touch:
            lastFrameDescription = """
            touch 序号 \(frame.sequence) 点数 \(frame.contacts.count) \
            灵敏度 \(frame.sensitivityPercent)% 自然滚动 \(frame.naturalScrolling)
            """
        }
    }
}
