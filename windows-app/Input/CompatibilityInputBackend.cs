using MoTouchPad.Windows.Model;

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

namespace MoTouchPad.Windows.Input;

internal sealed class CompatibilityInputBackend : IInputBackend
{
    private readonly MouseFallback _fallback = new();

    public string Name => "鼠标兼容模式";

    public void Submit(TouchFrame frame) => _fallback.Submit(frame);

    public void Reset() => _fallback.Reset();

    public void Dispose() => _fallback.Reset();
}
