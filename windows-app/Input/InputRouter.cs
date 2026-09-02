using MoTouchPad.Windows.Model;

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

namespace MoTouchPad.Windows.Input;

internal enum InputBackendMode
{
    Compatibility,
    ExperimentalVhf
}

internal sealed class InputRouter : IDisposable
{
    private readonly object _sync = new();
    private readonly CompatibilityInputBackend _compatibility = new();
    private readonly VhfInputBackend? _vhf;
    private IInputBackend _active;

    public InputRouter()
    {
        _vhf = VhfInputBackend.TryCreate();
        _active = _compatibility;
        Mode = InputBackendMode.Compatibility;
    }

    public InputBackendMode Mode { get; private set; }

    public bool DriverAvailable => _vhf?.IsAvailable == true;

    public string ActiveBackendName => _active.Name;

    public bool SetMode(InputBackendMode mode, out string message)
    {
        lock (_sync)
        {
            if (mode == InputBackendMode.ExperimentalVhf && !DriverAvailable)
            {
                message = "未检测到 VHF 驱动，继续使用鼠标兼容模式。";
                return false;
            }

            _active.Reset();
            _active = mode == InputBackendMode.ExperimentalVhf
                ? _vhf!
                : _compatibility;
            Mode = mode;
            message = $"输入后端已切换为：{_active.Name}。";
            return true;
        }
    }

    public bool Submit(TouchFrame frame, out string? error)
    {
        lock (_sync)
        {
            try
            {
                _active.Submit(frame);
                error = null;
                return true;
            }
            catch (Exception exception) when (ReferenceEquals(_active, _vhf))
            {
                _vhf?.Reset();
                _vhf?.Dispose();
                _active = _compatibility;
                Mode = InputBackendMode.Compatibility;
                _compatibility.Reset();
                error = $"VHF 驱动通信失败：{exception.Message}；已切换到鼠标兼容模式，当前帧不重放。";
                return false;
            }
        }
    }

    public void Reset()
    {
        lock (_sync) _active.Reset();
    }

    public void Dispose()
    {
        lock (_sync)
        {
            _active.Reset();
            _vhf?.Dispose();
            _compatibility.Dispose();
        }
    }
}
