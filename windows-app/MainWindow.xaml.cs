using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using MoTouchPad.Windows.Input;
using MoTouchPad.Windows.Protocol;

namespace MoTouchPad.Windows;

public partial class MainWindow : Window
{
    private const int Port = 47651;
    private readonly MouseFallback _fallback = new();
    private DriverClient? _driver;
    private TcpClient? _client;
    private CancellationTokenSource? _connectionCancellation;
    private bool _connecting;
    private bool _adbForwardActive;

    public MainWindow()
    {
        InitializeComponent();
        _driver = DriverClient.TryOpen();
        UpdateDriverStatus();
        Closed += (_, _) => Disconnect();
        AppendLog("应用已启动。");
    }

    private async void ConnectButton_OnClick(object sender, RoutedEventArgs e)
    {
        if (_client is not null || _connecting)
        {
            Disconnect();
            return;
        }

        await ConnectAsync();
    }

    private async void IpAddressTextBox_OnKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter && _client is null && !_connecting)
        {
            await ConnectAsync();
        }
    }

    private async void UsbConnectButton_OnClick(object sender, RoutedEventArgs e)
    {
        if (_client is not null || _connecting)
        {
            Disconnect();
            return;
        }

        try
        {
            SetStatus("正在检测 USB 设备…", null);
            UsbConnectButton.IsEnabled = false;
            var state = await RunAdbAsync("get-state");
            if (!state.StandardOutput.Contains("device", StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException(
                    "未找到已授权的 Android USB 设备，请开启 USB 调试并确认授权。");
            }

            var forward = await RunAdbAsync($"forward tcp:{Port} tcp:{Port}");
            if (forward.ExitCode != 0)
            {
                throw new InvalidOperationException(forward.StandardError.Trim());
            }

            _adbForwardActive = true;
            IpAddressTextBox.Text = IPAddress.Loopback.ToString();
            AppendLog($"ADB 已将本机端口 {Port} 转发至 Android。");
            await ConnectAsync();
        }
        catch (Exception exception)
        {
            AppendLog($"USB 连接失败：{exception.Message}");
            SetStatus("USB 连接失败", false);
        }
        finally
        {
            UsbConnectButton.IsEnabled = true;
        }
    }

    private async Task ConnectAsync()
    {
        var addressText = IpAddressTextBox.Text.Trim();
        if (!IPAddress.TryParse(addressText, out var address))
        {
            SetStatus("请输入有效的 IPv4 地址", false);
            return;
        }

        _connecting = true;
        ConnectButton.Content = "取消";
        IpAddressTextBox.IsEnabled = false;
        SetStatus("正在连接…", null);
        AppendLog($"连接 {address}:{Port}…");
        _connectionCancellation = new CancellationTokenSource();

        try
        {
            var client = new TcpClient { NoDelay = true };
            _client = client;
            await client.ConnectAsync(address, Port, _connectionCancellation.Token);
            SetStatus("Android 设备已连接", true);
            ConnectButton.Content = "断开";
            AppendLog("连接成功，开始接收触控帧。");

            await ReceiveLoopAsync(client, _connectionCancellation.Token);
        }
        catch (OperationCanceledException)
        {
            AppendLog("连接已取消。");
        }
        catch (Exception exception)
        {
            AppendLog($"连接中断：{exception.Message}");
            SetStatus("连接失败", false);
        }
        finally
        {
            _connecting = false;
            Disconnect();
        }
    }

    private async Task ReceiveLoopAsync(TcpClient client, CancellationToken cancellationToken)
    {
        await using var stream = client.GetStream();
        using var loopCancellation =
            CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        var heartbeat = SendHeartbeatAsync(stream, loopCancellation.Token);
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                var frame = await TouchFrame.ReadAsync(stream, cancellationToken);
                if (frame.Type == FrameType.Hello)
                {
                    AppendLog($"协议握手完成，版本 1，序号 {frame.Sequence}。");
                    continue;
                }

                if (_driver is not null)
                {
                    try
                    {
                        _driver.Submit(frame);
                        // Keep the raw VHF precision report available while using
                        // the compatibility path for the desktop pointer and gestures
                        // on Windows builds that do not route a virtual PTP device.
                        _fallback.Submit(frame);
                        continue;
                    }
                    catch (Exception exception)
                    {
                        AppendLog($"驱动通信失败，切换到鼠标兼容模式：{exception.Message}");
                        _driver.Dispose();
                        _driver = null;
                        UpdateDriverStatus();
                    }
                }
                _fallback.Submit(frame);
            }
        }
        finally
        {
            await loopCancellation.CancelAsync();
            try
            {
                await heartbeat;
            }
            catch (OperationCanceledException)
            {
                // Normal connection shutdown.
            }
        }
    }

    private static async Task SendHeartbeatAsync(
        NetworkStream stream,
        CancellationToken cancellationToken)
    {
        var heartbeat = new byte[] { 0x7F };
        while (!cancellationToken.IsCancellationRequested)
        {
            await stream.WriteAsync(heartbeat, cancellationToken);
            await stream.FlushAsync(cancellationToken);
            await Task.Delay(TimeSpan.FromSeconds(1), cancellationToken);
        }
    }

    private void Disconnect()
    {
        _connectionCancellation?.Cancel();
        _connectionCancellation?.Dispose();
        _connectionCancellation = null;
        _client?.Dispose();
        _client = null;

        if (_adbForwardActive)
        {
            _adbForwardActive = false;
            _ = RunAdbAsync($"forward --remove tcp:{Port}");
        }

        if (IsLoaded)
        {
            IpAddressTextBox.IsEnabled = true;
            ConnectButton.Content = "连接";
            UsbConnectButton.Content = "USB 连接";
            if (!_connecting) SetStatus("等待连接", null);
        }
    }

    private static async Task<ProcessResult> RunAdbAsync(string arguments)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = "adb",
            Arguments = arguments,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        using var process = Process.Start(startInfo)
            ?? throw new InvalidOperationException("无法启动 adb。");
        var standardOutput = await process.StandardOutput.ReadToEndAsync();
        var standardError = await process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        return new ProcessResult(process.ExitCode, standardOutput, standardError);
    }

    private void UpdateDriverStatus()
    {
        DriverStatusText.Text = _driver is null
            ? "鼠标兼容模式（未检测到驱动）"
            : "Precision Touchpad 驱动已就绪";
        DriverStatusText.Foreground = _driver is null
            ? (Brush)FindResource("MutedBrush")
            : (Brush)FindResource("PrimaryBrush");
    }

    private void SetStatus(string text, bool? connected)
    {
        StatusText.Text = text;
        StatusDot.Fill = connected switch
        {
            true => new SolidColorBrush(Color.FromRgb(80, 220, 148)),
            false => new SolidColorBrush(Color.FromRgb(255, 102, 102)),
            _ => new SolidColorBrush(Color.FromRgb(255, 177, 66))
        };
    }

    private void AppendLog(string text)
    {
        Dispatcher.Invoke(() =>
        {
            LogTextBox.AppendText($"[{DateTime.Now:HH:mm:ss}] {text}{Environment.NewLine}");
            LogTextBox.ScrollToEnd();
        });
    }

    private sealed record ProcessResult(
        int ExitCode,
        string StandardOutput,
        string StandardError);
}
