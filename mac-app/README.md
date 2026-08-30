# MoTouchPad for macOS

接收 iOS / Android 触控快照并注入桌面指针的 macOS 端（骨架）。

## 技术路线

- SwiftUI App，SwiftPM 构建，无需 Xcode 工程文件。
- 传输：`Network.framework` 的 `NWConnection` 连接触控端 TCP `47651`，
  每秒发送 `0x7F` 心跳（与 Windows 端一致）。
- 协议：MoTouchPad protocol v1 解码（`protocol/PROTOCOL.md`），
  流式缓冲 + 定长帧切分。
- 输入注入：CoreGraphics `CGEvent` 合成移动 / 点击 / 滚轮，
  捏合缩放走 `Ctrl + 滚轮`，与 Windows 兼容层同策略。

## 构建与运行

```sh
cd mac-app
swift build
swift run
```

## 骨架范围（当前状态）

- 协议 v1 解码器与流式切帧。
- TCP 连接管理与心跳。
- `CGEvent` 指针注入原语（移动 / 左右键 / 滚轮 / Ctrl+滚轮）。
- 连接与帧预览的最小 UI。

## TODO

- 双指滚动 / 捏合 / 轻点的手势状态机（参照 `MouseFallback` 的证据竞争设计）。
- 驱动通道：接入 `mac-driver` 后优先提交虚拟触控板报告，`CGEvent` 作兼容层。
- 菜单栏常驻与开机自启。
