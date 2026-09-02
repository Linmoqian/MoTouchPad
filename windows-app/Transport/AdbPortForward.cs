using System.Diagnostics;

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

namespace MoTouchPad.Windows.Transport;

internal sealed class AdbPortForward : IDisposable
{
    private readonly int _port;
    private readonly object _sync = new();
    private bool _active;

    public AdbPortForward(int port)
    {
        _port = port;
    }

    public bool IsActive
    {
        get
        {
            lock (_sync) return _active;
        }
    }

    public async Task StartAsync(CancellationToken cancellationToken = default)
    {
        var state = await RunAsync(["get-state"], cancellationToken);
        if (state.ExitCode != 0 ||
            !state.StandardOutput.Contains("device", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException(
                "未找到已授权的 Android USB 设备，请开启 USB 调试并确认授权。");
        }

        var forward = await RunAsync(
            ["forward", $"tcp:{_port}", $"tcp:{_port}"],
            cancellationToken);
        if (forward.ExitCode != 0)
        {
            throw new InvalidOperationException(
                string.IsNullOrWhiteSpace(forward.StandardError)
                    ? "adb 端口转发失败。"
                    : forward.StandardError.Trim());
        }

        lock (_sync) _active = true;
    }

    public async Task StopAsync(CancellationToken cancellationToken = default)
    {
        lock (_sync)
        {
            if (!_active) return;
            _active = false;
        }

        var result = await RunAsync(
            ["forward", "--remove", $"tcp:{_port}"],
            cancellationToken);
        if (result.ExitCode != 0 &&
            !result.StandardError.Contains("does not exist", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException(result.StandardError.Trim());
        }
    }

    public void Dispose()
    {
        _ = StopIgnoringErrorsAsync();
    }

    private async Task StopIgnoringErrorsAsync()
    {
        try
        {
            await StopAsync();
        }
        catch
        {
            // Application shutdown is best effort; do not surface an
            // unobserved cleanup exception from the finalizer-like path.
        }
    }

    private static async Task<ProcessResult> RunAsync(
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = "adb",
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        foreach (var argument in arguments) startInfo.ArgumentList.Add(argument);

        using var process = Process.Start(startInfo)
            ?? throw new InvalidOperationException("无法启动 adb，请确认 adb 已加入 PATH。");
        var standardOutputTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var standardErrorTask = process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);
        await Task.WhenAll(standardOutputTask, standardErrorTask);
        return new ProcessResult(
            process.ExitCode,
            await standardOutputTask,
            await standardErrorTask);
    }

    private sealed record ProcessResult(
        int ExitCode,
        string StandardOutput,
        string StandardError);
}
