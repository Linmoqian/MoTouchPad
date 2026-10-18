# MoTouchPad 架构说明

项目包含四个应用端与两个独立驱动实验模块。应用构建和运行不依赖 DriverKit、
WDK 或驱动签名。

## 数据流与责任

    Android / iOS UI
        -> 原始触控快照 Model
        -> protocol v1 codec
        -> TCP / ADB Forward
        -> 桌面 Protocol decoder
        -> TouchFrame Router
        -> 平台 Input backend
        -> Windows SendInput / macOS CGEvent

移动端只采集触点、坐标、压力、尺寸和设置，不预计算手势。协议的网络记录经过
长度、字节序和字段检查后成为 TouchFrame，输入层不依赖网络字节布局。

| 目录 | 职责 |
|---|---|
| protocol/ | 唯一线协议源与黄金样例 |
| android-app/.../ui/、ios-app/App/UI/ | 触控采集与状态、设置界面 |
| 移动端 Model / model | 原生快照、触点和设置 |
| 移动端 Protocol / protocol | 小端编码和校验 |
| 移动端 Transport / transport | 监听、心跳、连接与有界发送队列 |
| mac-app/Sources/MoTouchPadCore/ | macOS 原生模型、协议、流解码与纯手势状态机 |
| core-rust/ | 独立 Rust codec、纯手势状态机与 C ABI 评估原型 |
| tools/RustCoreComparison/ | 相同轨迹的 Swift / Rust 动作对照与调用成本测量 |
| mac-app/Sources/MoTouchPadMac/App/ | 窗口、接收状态与快捷键偏好 |
| mac-app/Sources/MoTouchPadMac/Transport/ | NWConnection 生命周期、心跳与批量派发 |
| mac-app/Sources/MoTouchPadMac/Input/ | 动作执行器、CGEvent sink 与屏幕坐标适配 |
| windows-app/UI/ | WPF 状态与连接控件 |
| windows-app/Model/、Protocol/ | 模型与 codec / stream decoder |
| windows-app/Transport/ | TCP 接收、心跳与 ADB 转发 |
| windows-app/Input/ | 兼容输入、VHF 实验输入与单路路由 |
| windows-driver/ | Windows IOCTL 与 HID / VHF 实验 |
| mac-driver/ | DriverKit 独立实验占位 |

## 发送背压与接收延迟

Android / iOS 发送端使用 32 帧有界队列。只合并同触点、同设置会话中方向连续的
运动快照。hello、触点增减、UP、取消、设置变化、反向和明显转弯形成边界，保留
顺序。队列满且无法合并时结束连接，桌面端 reset，避免丢 UP 或回放长期积压动作。

iOS 在采集线程入队，再由单个发送泵消费，最多一帧正在发送，避免 GCD 或网络层
堆积发送任务。Android 先取出会话与输出流，再在状态锁外阻塞写入；替换连接会
关闭旧 socket，旧写入失败只能清理对应旧连接。两端 socket 均启用 TCP noDelay。

macOS 用 TouchFrameStreamDecoder 在原缓冲内按偏移读取完整帧，只复制末尾残帧。
每批只向主线程派发一次回调；消费回调时再次检查连接代际，旧连接回调不污染新
会话。所有输入动作逐帧执行，接收状态显示最多每秒刷新 10 次。Windows 接收端
同样显式启用 NoDelay。

## Windows 输入后端

默认使用 CompatibilityInputBackend / MouseFallback。只有 UI 显式启用实验性
VHF 后，InputRouter 才提交 VhfInputBackend，同一帧只进入一个后端。

- 驱动打开失败：保留兼容层并提示不可用。
- 驱动提交失败：释放驱动、重置状态并切换回兼容层，不重放失败帧。
- 断连或取消：Reset 清理按键与手势状态。
- UI 显示当前后端，不把驱动句柄打开等同于系统消费 Precision Touchpad 报告。

兼容层解释单指移动/轻触、双指滚动/缩放/右键。灵敏度只影响指针移动，自然滚动
只改变滚动方向。三指及以上静默直到全部抬起；UP 用于完成点击和清理。

## macOS 输入后端

MoTouchPadCore 将原始快照解释为 GestureAction，动作执行器使用用户偏好调用
可替换 MacInputSink。生产 sink 使用 CGEvent；测试使用记录型 sink，不注入真实
系统输入。屏幕换算使用逻辑坐标，处理 AppKit / CoreGraphics 坐标原点差异。

- 单指：相对移动、轻点、系统双击、轻点后再次按住移动的左键拖移。
- 双指：右键、纵横滚动、快速横扫的前进/后退、捏合、旋转和智能缩放。
- 三指：轻点查词、快速上滑 App Exposé、停留/移动进入持续左键拖移。
- 四指：轻点切换应用、调度中心、App Exposé、空间切换、张开/合拢的桌面/应用启动器。
- 五指、取消或已判定会话的触点 ID / 数量变化：清理并抑制直至全部抬起。

触点 ID 用 256 位掩码替代动态 Set，几何统计单次遍历，减少临时分配。单指输出
阈值为 0.004；首次指针、滚动、缩放输出保留分类前积累量。三指停留使用桌面
计时器，静止触控不需要额外网络帧。断连、取消和重连释放所有模拟拖移状态。

CGEvent 通过鼠标、滚轮和键盘组合键模拟动作。系统窗口动作与应用缩放/旋转使用
本机 UserDefaults 中一套全局可编辑绑定；未绑定命令静默。默认未配置智能缩放，
双指右键立即触发；配置后才启用 0.30 秒双击等待。旧偏好自动补入新增动作，明确
清除的绑定仍保持未设置。启动台在较新 macOS 中可能呈现为 Apps。

## 权限与验证

macOS 输入需要辅助功能授权，iOS 本地 TCP 连接需要本地网络权限。iOS 的网络
状态和错误回调由应用模型切回主线程更新 UI。驱动实验不进入应用路由。

    python3 tools/validate_protocol_fixtures.py
    cd mac-app
    swift build
    swift test
    swift run -c release TouchPipelineBenchmark

Release 微基准测量 CPU 解码和手势处理耗时，不等于端到端网络延迟；两设备单调
时钟不共享原点，不能直接相减计算单向延迟。回环 TCP 测试验证实际传输中的分片、
合包与顺序。真实 Wi-Fi 延迟和目标 App 的手势效果需在设备上验收。

共享核心原型通过 C ABI 借用完整帧，输出固定容量平台无关动作。单句柄必须串行
调用，计时器由宿主驱动，reset 产生的拖移结束动作仍由平台输入层执行。应用主链
继续使用原生核心，原型的正确性与性能评估见 [Rust 核心评估](rust-core-evaluation.md)。

Android CI 使用 JDK 21 和仓库 Gradle wrapper；macOS 使用 SwiftPM；iOS 使用
无签名 xcodebuild；Windows 使用 .NET 9。CI 只构建和测试，不打包、签名或发布
驱动，不上传安装包。
