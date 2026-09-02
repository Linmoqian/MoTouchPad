using System.Net;
using System.Net.Sockets;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using MoTouchPad.Windows.Input;
using MoTouchPad.Windows.Model;
using MoTouchPad.Windows.Protocol;
using MoTouchPad.Windows.Transport;

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

namespace MoTouchPad.Windows;

public partial class MainWindow : Window
{
    private const int Port = TouchFrameCodec.Port;
    private readonly InputRouter _inputRouter = new();
    private readonly TcpTouchReceiver _receiver = new();
    private readonly AdbPortForward _adbPortForward = new(Port);
    private TcpClient? _client;
    private CancellationTokenSource? _connectionCancellation;
    private bool _connecting;

    public MainWindow()
    {
        InitializeComponent();
        UpdateDriverStatus();
        Closed += (_, _) =>
        {
            Disconnect();
            _adbPortForward.Dispose();
            _inputRouter.Dispose();
        };
        AppendLog("应用已启动。默认使用鼠标兼容模式。");
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
            await _adbPortForward.StartAsync();
            IpAddressTextBox.Text = IPAddress.Loopback.ToString();
            AppendLog($"ADB 已将本机端口 {Port} 转发至 Android。");
            await ConnectAsync();
        }
        catch (Exception exception)
        {
            AppendLog($"USB 连接失败：{exception.Message}");
            SetStatus("USB 连接失败", false);
            await StopAdbForwardAsync();
        }
        finally
        {
            UsbConnectButton.IsEnabled = true;
        }
    }

    private async Task ConnectAsync()
    {
        var addressText = IpAddressTextBox.Text.Trim();
        if (!IPAddress.TryParse(addressText, out var address) ||
            address.AddressFamily != AddressFamily.InterNetwork)
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
        var cancellationToken = _connectionCancellation.Token;

        try
        {
            var client = new TcpClient { NoDelay = true };
            _client = client;
            await client.ConnectAsync(address, Port, cancellationToken);
            SetStatus("Android 设备已连接", true);
            ConnectButton.Content = "断开";
            AppendLog("连接成功，开始接收触控帧。");

            await _receiver.ReceiveAsync(client, HandleFrame, cancellationToken);
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
            _inputRouter.Reset();
            _connecting = false;
            Disconnect();
        }
    }

    private void HandleFrame(TouchFrame frame)
    {
        if (frame.Type == FrameType.Hello)
        {
            AppendLog($"协议握手完成，版本 1，序号 {frame.Sequence}。");
            return;
        }

        if (!_inputRouter.Submit(frame, out var error))
        {
            if (!string.IsNullOrWhiteSpace(error)) AppendLog(error);
            Dispatcher.BeginInvoke(new Action(UpdateDriverStatus));
        }
    }

    private void Disconnect()
    {
        _connectionCancellation?.Cancel();
        _connectionCancellation?.Dispose();
        _connectionCancellation = null;
        _client?.Dispose();
        _client = null;
        _inputRouter.Reset();

        if (_adbPortForward.IsActive) _ = StopAdbForwardAsync();

        if (IsLoaded)
        {
            IpAddressTextBox.IsEnabled = true;
            ConnectButton.Content = "连接";
            UsbConnectButton.Content = "USB 连接";
            if (!_connecting) SetStatus("等待连接", null);
        }
    }

    private async Task StopAdbForwardAsync()
    {
        try
        {
            await _adbPortForward.StopAsync();
            AppendLog("ADB 端口转发已移除。");
        }
        catch (Exception exception)
        {
            AppendLog($"移除 ADB 端口转发失败：{exception.Message}");
        }
    }

    private void ExperimentalDriverCheckBox_OnClick(object sender, RoutedEventArgs e)
    {
        var mode = ExperimentalDriverCheckBox.IsChecked == true
            ? InputBackendMode.ExperimentalVhf
            : InputBackendMode.Compatibility;
        if (!_inputRouter.SetMode(mode, out var message))
        {
            ExperimentalDriverCheckBox.IsChecked = false;
        }

        AppendLog(message);
        UpdateDriverStatus();
    }

    private void UpdateDriverStatus()
    {
        var availability = _inputRouter.DriverAvailable ? "VHF 可用" : "VHF 不可用";
        DriverStatusText.Text = $"当前后端：{_inputRouter.ActiveBackendName} · {availability}";
        DriverStatusText.Foreground = _inputRouter.Mode == InputBackendMode.ExperimentalVhf
            ? (Brush)FindResource("PrimaryBrush")
            : (Brush)FindResource("MutedBrush");
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
        if (!Dispatcher.CheckAccess())
        {
            Dispatcher.BeginInvoke(new Action(() => AppendLog(text)));
            return;
        }

        LogTextBox.AppendText($"[{DateTime.Now:HH:mm:ss}] {text}{Environment.NewLine}");
        LogTextBox.ScrollToEnd();
    }
}
