# Development guide

应用分层、数据流和输入 backend 选择见 [architecture.md](architecture.md)。
驱动实验不属于应用 CI 成功条件。

## Android

要求：

- Android SDK 36
- JDK 21
- Android 8.0（API 26）或更高版本设备

构建、lint 和单元测试：

    cd android-app
    ./gradlew :app:assembleDebug :app:lintDebug :app:testDebugUnitTest

安装：

    adb install -r app/build/outputs/apk/debug/app-debug.apk

打开应用后，它会进入横屏沉浸模式并显示设备 IP 和 TCP 端口。

## Windows application

构建：

    dotnet build windows-app/MoTouchPad.Windows.csproj

运行：

    dotnet run --project windows-app/MoTouchPad.Windows.csproj

输入 Android 设备显示的 IP 后选择连接。USB 开发需要打开 USB 调试并授权
电脑，然后选择 USB 连接；应用会检查 adb get-state、建立端口转发，并在
连接关闭时移除转发。

默认输入 backend 是 MouseFallback。只有勾选实验性 VHF 后才会提交驱动；
VHF 打开失败或提交失败均回到兼容层，失败帧不重放。

## Apple applications

macOS：

    cd mac-app
    swift build
    swift test
    swift run MoTouchPadMac

macOS CGEvent 注入需要辅助功能权限。应用按当前显示器的逻辑坐标换算移动，
不直接使用 Retina 像素尺寸。

iOS：

    xcodebuild -project ios-app/ios-app.xcodeproj -scheme MoTouchPad -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO

iOS 需要本地网络权限才能接受电脑连接。触控视图使用本地坐标并开启多指
触控；监听失败和连接失败通过 UI 状态暴露。

## Protocol fixtures

    python3 tools/validate_protocol_fixtures.py
    dotnet run --project tools/ProtocolSmokeTest/ProtocolSmokeTest.csproj

协议字节布局、分片/合帧规则和非法值处理见 [protocol/PROTOCOL.md](../protocol/PROTOCOL.md)。

## Drivers

Windows 驱动需要 Visual Studio 2022、WDK 10.0.28000.0 和管理员权限：

    msbuild windows-driver/MoTouchPad.Driver.vcxproj /p:Configuration=Debug /p:Platform=x64

开发期间安装 INF 可能需要测试签名。修改系统启动策略前应确认正在使用专用
开发机或虚拟机。驱动不进入应用 CI，也不参与应用构建成功条件。

mac-driver/ 目前只保留 DriverKit 实验占位，不接触网络和 UI。

## Security

开发协议仅面向可信局域网，未加入配对、身份验证或加密。不要把 TCP 47651
暴露到公网。
