# MoTouchPad for iOS

将 iPhone / iPad 作为触控板的 SwiftUI/UIKit 发送端。

## 技术路线

- SwiftUI + UIKit 桥接：UIViewRepresentable 包装的触控视图负责多指追踪。
- Network.framework 的 NWListener 监听 TCP 47651，与 Android 端使用同一
  protocol v1（见 protocol/PROTOCOL.md）。
- 每帧是完整原始快照，小端编码，队列满时丢旧保新。
- 入站方向只消费电脑的 0x7F 心跳，EOF 或网络错误会更新连接状态。
- 触控坐标以视图本地尺寸归一化，UP 快照发送一次后再发送无该联系人的
  快照。

## 构建

需要 Xcode 16 或更高版本：

    xcodebuild -project ios-app.xcodeproj -scheme MoTouchPad -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO

首次运行需要允许本地网络访问。权限用途由应用的 Info.plist 构建设置声明。

## 当前状态

- 协议 v1 编码器、共享 fixture harness 和快照序号器。
- TCP 服务端连接管理、心跳消费、监听/连接错误状态。
- 全屏多指触控采集、稳定触点 ID、灵敏度和自然滚动设置。

## 暂未覆盖

- USB（有线网络）连接识别。
- 正式发布签名和安装包流程。
