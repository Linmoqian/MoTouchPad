# Development guide

## Android

Requirements:

- Android SDK 36
- JDK 21
- Android device running Android 8.0 (API 26) or later

Build:

```powershell
cd android-app
.\gradlew.bat assembleDebug
```

Install:

```powershell
adb install -r app\build\outputs\apk\debug\app-debug.apk
```

Open MoTouchPad on the device. It enters landscape immersive mode and displays
the device IP and TCP port.

## Windows application

Build:

```powershell
dotnet build windows-app\MoTouchPad.Windows.csproj
```

Run:

```powershell
dotnet run --project windows-app\MoTouchPad.Windows.csproj
```

Enter the IP displayed by the Android device and select **Connect**.

For USB development, enable USB debugging on Android, authorize the PC, and
select **USB Connect**. The application checks `adb get-state`, creates an ADB
port forward, and removes it when the connection closes.

## Driver

The driver requires Visual Studio 2022 with WDK 10.0.28000.0. Open an elevated
Developer PowerShell:

```powershell
& "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\amd64\MSBuild.exe" `
  windows-driver\MoTouchPad.Driver.vcxproj /p:Configuration=Debug /p:Platform=x64
```

During development, enable Windows test signing and install the generated INF
from an elevated terminal. Enabling test signing changes the machine boot
policy, so it is intentionally not automated by this repository.

```powershell
bcdedit /set testsigning on
# Restart Windows, then:
devcon install path\to\MoTouchPad.Driver.inf "Root\MoTouchPad"
```

For an existing device node, replace `install` with `update`.

For public distribution the driver package must be submitted for Microsoft
signing.

The local WDK 10.0.28000 build tasks require Visual Studio's Spectre-mitigated
MSVC libraries for a release build. Debug builds disable Spectre library
selection so development can proceed, but release packaging intentionally does
not.

## Security and network

The current development protocol is intentionally LAN-only and unencrypted.
Do not expose TCP port `47651` to the public internet. Authenticated pairing and
encrypted control traffic are planned before release.
