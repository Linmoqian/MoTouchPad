# MoTouchPad for macOS

接收 iOS / Android 触控快照并注入桌面指针的 macOS 端。

## 技术路线

- SwiftUI App，SwiftPM 构建，无需 Xcode 工程文件。
- MoTouchPadCore 承载 macOS 应用内部共享的 Model、Protocol 和手势状态机。
- NWConnection 连接触控端 TCP 47651，每秒发送 0x7F 心跳。
- 流式缓冲按 protocol v1 帧头切分，支持 TCP 分片和多帧合并。
- CGEvent 注入移动、左右键、滚轮和 Ctrl + 滚轮缩放。

## 构建与运行

    cd mac-app
    swift build
    swift test
    swift run

首次注入鼠标需要在系统设置的隐私与安全性 → 辅助功能中授权 MoTouchPad。

## 当前状态

- 协议 v1 解码、非法帧拒绝、fixture round-trip 和流式切帧测试。
- TCP 连接重连、心跳、连接身份校验和旧回调隔离。
- 单指移动/轻触、双指滚动/捏合/轻触的手势状态机。
- 使用当前显示器逻辑坐标的正式 CGEvent 输入 backend。

mac-driver/ 仍是独立 DriverKit 实验占位，不进入 macOS 应用路由。
