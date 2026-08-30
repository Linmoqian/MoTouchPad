# MoTouchPad DriverKit 驱动（骨架）

对应 `windows-driver/` 的 KMDF + VHF 方案：在 macOS 上创建一个虚拟
Precision Touchpad（HID）设备，把触控快照直接注入系统 HID 栈。

## 技术路线

- DriverKit（DEXT）用户空间驱动，`IOUserHIDDevice` 子类。
- 复用 Windows 驱动已验证的 PTP HID Report Descriptor 思路：
  Digitizers Usage Page、5 个 Finger collection（Confidence + Tip Switch +
  Contact Identifier）、Scan Time、Contact Count 与按钮位。
- 报告来源：由 `mac-app` 通过用户客户端（IOUserClient）提交，
  对应 Windows 端 `IOCTL_MOTOUCHPAD_SUBMIT_FRAME` → `VhfReadReportSubmit` 的链路。

## 当前状态（骨架，不可构建）

- `MoTouchPadDriver/` 只含占位类型与 Info.plist 骨架。
- 构建依赖 Xcode 的 DriverKit target、`com.apple.developer.driverkit`
  系列 entitlement 及 Apple 签名授权，需另行申请开发配置。

## TODO

- 补齐 `IOUserHIDDevice` 生命周期实现与 report descriptor。
- 定义 `mac-app` → 驱动的用户客户端接口（提交触控帧）。
- 确定系统扩展激活与用户授权流程。
