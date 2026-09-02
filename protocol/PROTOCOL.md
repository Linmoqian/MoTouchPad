# MoTouchPad protocol v1

本文件是网络线协议的唯一来源。协议固定使用 TCP 端口 47651，不引入跨语言
运行库、代码生成或新的 wire version。移动端发送原始触控快照，桌面端负责
手势解释和平台输入注入。

## 网络帧

每帧都是一份完整快照。TCP 可能把一帧拆成多次读取，也可能把多帧合并在一次
读取中；接收端必须按帧头中的联系人数量切分，不能依赖 TCP message 边界。

所有整数和 IEEE-754 binary32 浮点数均为 little-endian。

### 24 字节帧头

| 偏移 | 类型 | 字段 |
|---:|---|---|
| 0 | uint32 | Magic 0x3150544D，字节序列为 4D 54 50 31（MTP1） |
| 4 | uint8 | Version，当前必须为 1 |
| 5 | uint8 | Type：1=hello，2=touch |
| 6 | uint16 | Flags，v1 必须为 0 |
| 8 | uint32 | Sequence，发送端单调递增序号 |
| 12 | int64 | 触控端单调时钟纳秒时间戳 |
| 20 | uint8 | Contact count，范围 0...5 |
| 21 | uint8 | Physical button bits |
| 22 | uint8 | Pointer sensitivity，50...200；0 按 100 解释 |
| 23 | uint8 | Settings flags，bit 0 为自然滚动，其余位必须为 0 |

hello 帧的联系人数量必须为 0。touch 帧可以是空快照。

### 24 字节联系人记录

touch 帧在帧头后按联系人数量追加记录：

| 记录偏移 | 类型 | 字段 |
|---:|---|---|
| 0 | uint8 | Stable pointer ID |
| 1 | uint8 | State：0=UP，1=TOUCHING |
| 2 | uint16 | Reserved，必须为 0 |
| 4 | float32 | Normalized X，有限值 0...1 |
| 8 | float32 | Normalized Y，有限值 0...1 |
| 12 | float32 | Pressure，有限值 0...1 |
| 16 | float32 | Normalized touch major，有限值 0...1 |
| 20 | float32 | Normalized touch minor，有限值 0...1 |

坐标和触点尺寸相对于移动端触控视图，而不是屏幕 Retina 像素。每帧中的
联系人集合是该时刻的快照。UP 联系人只发送一次，随后发送不包含它的快照；
接收端使用这个 UP 完成点击判定和状态清理。
取消触控可以直接发送不含 UP 联系人的空 touch 快照；没有 UP 的空快照只用于
清理状态，不得触发点击。

### 合法类型和方向

- 移动端到电脑：hello 和 touch。
- 电脑到移动端：单字节 0x7F，每秒一次的传输心跳。
- 移动端收到的入站字节只能是 0x7F；未知控制字节是协议错误。
- 心跳不是触控帧，不能交给 codec 解码。

### 错误处理

以下情况必须直接判定为协议错误并结束当前连接或丢弃当前协议会话：

- Magic、Version 或 Type 不合法；
- 联系人数量大于 5；
- 帧长度不等于 24 + count × 24；
- hello 携带联系人；
- Flags 或保留字段不为 0；
- 联系人 State 不是 0 或 1；
- 灵敏度不是 0 或 50...200；
- 坐标、压力、触点尺寸不是有限的 0...1 数值。

codec 的公共边界保持为：

    decode(bytes or stream) -> TouchFrame
    encode(TouchFrame) -> bytes

stream decoder 负责完整读取帧并支持分片、合帧；纯 bytes decoder 只接受恰好
一帧的字节，不应静默忽略尾部数据。

## 驱动 IOCTL（独立实验协议）

Windows 应用到 Windows Driver 的固定 128 字节 IOCTL 结构不属于网络协议，
由 windows-driver/ 自行维护。应用主链默认只使用鼠标兼容后端；VHF 只有在
UI 显式启用实验模式时才会接收快照。mac-driver/ 同样不接入应用网络路由。
