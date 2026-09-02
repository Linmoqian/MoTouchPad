// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

namespace MoTouchPad.Windows.Model;

internal enum FrameType : byte
{
    Hello = 1,
    Touch = 2
}

internal sealed record TouchContact(
    byte Id,
    bool Touching,
    float X,
    float Y,
    float Pressure,
    float Major,
    float Minor);

internal sealed record TouchFrame(
    FrameType Type,
    uint Sequence,
    long TimestampNanos,
    byte Buttons,
    byte SensitivityPercent,
    bool NaturalScrolling,
    IReadOnlyList<TouchContact> Contacts);
