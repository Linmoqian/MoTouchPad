using MoTouchPad.Windows.Model;

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

namespace MoTouchPad.Windows.Input;

internal interface IInputBackend : IDisposable
{
    string Name { get; }

    void Submit(TouchFrame frame);

    void Reset();
}
