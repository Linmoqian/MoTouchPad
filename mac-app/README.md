# MoTouchPad for macOS

接收 iOS / Android 触控快照并注入桌面指针的 macOS 端。

## 技术路线

- SwiftUI App，SwiftPM 构建，无需 Xcode 工程文件。
- MoTouchPadCore 承载 macOS 应用内部共享的 Model、Protocol 和手势状态机。
- NWConnection 连接触控端 TCP 47651，每秒发送 0x7F 心跳。
- 流式缓冲按 protocol v1 帧头切分，支持 TCP 分片和多帧合并。
- GestureRecognizer 只输出平台无关动作；CGEvent 输入层负责鼠标、滚轮和快捷键注入。
- 手势快捷键保存在本机 UserDefaults，可在窗口的“手势设置”中录制、清除或恢复默认值。

## 构建与运行

    cd mac-app
    swift build
    swift test
    swift run

首次注入鼠标和快捷键需要在系统设置的隐私与安全性 → 辅助功能中授权 MoTouchPad。

## 多点触控

| 触点 | 动作 | macOS 行为 |
|---|---|---|
| 单指 | 移动、轻点、连续两次轻点 | 相对指针、左键和系统双击 |
| 双指 | 轻点、纵向移动、慢速横移、快速横扫 | 延迟右键、滚动、水平滚动、前进/后退 |
| 双指 | 捏合、旋转、连续两次轻点 | 放大/缩小快捷键、旋转快捷键、智能缩放快捷键 |
| 三指 | 轻点、快速上滑、停留或拖移 | 查词、App Exposé、持续左键拖移 |
| 四指 | 上下左右快滑、整体张开/合拢 | 调度中心、App Exposé、空间切换、显示桌面/应用启动器 |

双指右键会等待 0.30 秒，以区分双指双击；未设置智能缩放时，第二次轻点会消耗该
手势但不发送按键。五指、取消帧、触点 ID 改变或断连会清理当前状态，绝不生成点击。

默认快捷键包括 `Command+[ / ]`、`Command+= / -`、`Control+Command+D`、
`Control+箭头`，以及带 Fn 的桌面/应用启动器快捷键。旋转和智能缩放默认未设置；
系统设置或不同 App 改写快捷键后，应在 MoTouchPad 的“手势设置”中同步修改。
所有绑定都发送给当前前台 App，不提供按 App 独立档案。
较新 macOS 可能将“启动台”显示为“Apps”；应用启动器的默认快捷键同样可修改。

## 当前状态

- 协议 v1 解码、非法帧拒绝、fixture round-trip 和流式切帧测试。
- TCP 连接重连、心跳、连接身份校验和旧回调隔离。
- 单至四指的纯 Swift 手势状态机、UP/取消/重连清理与延迟双指右键。
- 使用当前显示器逻辑坐标、可替换输入 sink 和快捷键动作执行器的正式 CGEvent backend。
- 手势判定、快捷键持久化和执行器均有无副作用单元测试；测试不会注入真实系统输入。

mac-driver/ 仍是独立 DriverKit 实验占位，不进入 macOS 应用路由。
