# MoTouchPad for iOS

将 iPhone / iPad 作为触控板的 SwiftUI 发送端（骨架）。

## 技术路线

- SwiftUI + UIKit 桥接：多指追踪使用 `UIViewRepresentable` 包装的
  `UIResponder` 触控回调，SwiftUI 手势不足以表达任意指点数。
- 传输：`Network.framework` 的 `NWListener` 监听 TCP `47651`，
  与 Android 端保持同一 MoTouchPad protocol v1（见 `protocol/PROTOCOL.md`）。
- 每帧完整快照、小端编码，队列满丢旧保新。
- 入站方向只消费 PC 的 `0x7F` 心跳字节，EOF 判定断连。

## 构建

需要 Xcode 16 或更高版本：

```sh
xcodebuild -project ios-app.xcodeproj -scheme MoTouchPad \
  -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
```

## 骨架范围（当前状态）

- 协议 v1 编码器与快照序号器。
- TCP 服务端连接管理与心跳消费。
- 全屏触控上报与状态岛 UI 占位。

## TODO

- 设置界面（灵敏度 / 自然滚动）与持久化。
- USB（有线网络）连接识别。
- 本地网络权限说明页与连接引导。
