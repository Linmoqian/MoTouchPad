# MoTouchPad 架构说明

MoTouchPad 分为四个应用端和两个独立驱动实验模块。应用链路的成功条件
不依赖任何 DriverKit、WDK 或签名环境。

## 端到端数据流

    Android / iOS UI
        -> 本地触控快照 Model
        -> Protocol codec
        -> TCP 或 ADB Forward Transport
        -> 桌面端 Protocol decoder
        -> TouchFrame Router
        -> 平台 Input backend
        -> Windows SendInput 或 macOS CGEvent

移动端只采集触点、坐标、压力、尺寸和设置，发送完整的原始快照；不在手机
上判断点击、滚动或缩放。桌面端依据平台能力解释同一份 TouchFrame。

## 目录责任

| 目录 | 唯一职责 |
|---|---|
| protocol/ | protocol v1 线格式、规则和黄金字节样例 |
| android-app/.../ui/ | Android 触控视图、状态岛和设置交互 |
| android-app/.../model/ | Android 原生快照、触点和设置模型 |
| android-app/.../protocol/ | Android little-endian codec |
| android-app/.../transport/ | TCP 服务端、心跳、连接和 ADB 相关网络状态 |
| ios-app/App/UI/ | SwiftUI/UIKit 触控采集和状态展示 |
| ios-app/App/Model/ | iOS 原生快照、稳定触点 ID 和序号 |
| ios-app/App/Protocol/ | iOS little-endian codec |
| ios-app/App/Transport/ | Network.framework listener、队列和心跳 |
| mac-app/Sources/MoTouchPadCore/ | macOS 应用内部共享的模型、协议和手势状态机 |
| mac-app/Sources/MoTouchPadMac/App/ | macOS SwiftUI 窗口和接收状态 |
| mac-app/Sources/MoTouchPadMac/Transport/ | NWConnection 生命周期和流切帧 |
| mac-app/Sources/MoTouchPadMac/Input/ | CGEvent 输入后端和屏幕坐标适配 |
| windows-app/UI/ | WPF 窗口、连接控件和后端状态 |
| windows-app/Model/ | C# 原生快照和触点模型 |
| windows-app/Protocol/ | C# codec 和 stream decoder |
| windows-app/Transport/ | TCP 接收、心跳和 ADB 端口转发 |
| windows-app/Input/ | 兼容输入、VHF 实验输入和后端路由 |
| windows-driver/ | 仅处理 Windows 驱动 IOCTL 和 HID/VHF |
| mac-driver/ | 仅保留 DriverKit 实验占位 |

Protocol 的网络记录不是业务模型：codec 负责长度、字节序和字段合法性，解码
后才得到各端的 TouchFrame。这样平台输入层不需要依赖网络字节布局。

## Windows 后端选择

Windows 启动时默认选择 CompatibilityInputBackend，也就是稳定的
MouseFallback。UI 显式勾选实验性 VHF 后，InputRouter 才会把后续帧交给
VhfInputBackend；同一时刻不会调用两个 backend。

- VHF 打开失败：保留兼容层并提示驱动不可用。
- VHF 提交失败：释放驱动、重置兼容层状态、切换回兼容层；失败帧不重放。
- 断开连接或取消触控：统一调用 Reset，避免按键、点击或双指模式残留。
- UI 显示当前实际后端和 VHF 探测结果，不把驱动句柄打开等同于系统已消费
  Precision Touchpad 报告。

## 共享行为契约

- 单指移动：相对指针移动。
- 单指轻触：左键。
- 双指轻触：右键。
- 双指移动：滚动；自然滚动只改变滚动方向。
- 双指间距变化：缩放；缩放不改变指针灵敏度。
- 灵敏度只影响单指指针移动。
- 三指及以上：静默，直到全部触点抬起。
- UP 联系人只完成一次点击判定，并用于清理状态。

macOS 使用 CGEvent，并以当前显示器的逻辑坐标和动态边界换算归一化移动；
Retina 像素尺寸不会直接进入移动比例。iOS 的 Network.framework 回调回到
主线程更新 UI，并声明本地网络权限。驱动实验不进入上述应用主链。

## 构建与验证

共享样例和 Python 结构检查：

    python3 tools/validate_protocol_fixtures.py

Android 使用仓库 Gradle wrapper 和 JDK 21；macOS 使用 SwiftPM；
iOS 使用无签名 xcodebuild；Windows 使用 .NET 9。GitHub Actions 只构建和
测试应用，不上传安装包，不签名、不发布、不打包驱动。
