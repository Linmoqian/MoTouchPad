using MoTouchPad.Windows.Model;

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

namespace MoTouchPad.Windows.Input;

internal sealed class VhfInputBackend : IInputBackend
{
    private DriverClient? _driver;

    private VhfInputBackend(DriverClient driver)
    {
        _driver = driver;
    }

    public string Name => "实验性 Precision Touchpad 驱动";

    public bool IsAvailable => _driver is not null;

    public static VhfInputBackend? TryCreate()
    {
        var driver = DriverClient.TryOpen();
        return driver is null ? null : new VhfInputBackend(driver);
    }

    public void Submit(TouchFrame frame)
    {
        (_driver ?? throw new InvalidOperationException("VHF driver is unavailable.")).Submit(frame);
    }

    public void Reset()
    {
        // Send one empty report so a disconnect or backend switch cannot leave
        // contacts pressed in the experimental HID path.
        if (_driver is null) return;
        try
        {
            _driver.Submit(new TouchFrame(
                FrameType.Touch,
                Sequence: 0,
                TimestampNanos: 0,
                Buttons: 0,
                SensitivityPercent: 100,
                NaturalScrolling: false,
                Contacts: []));
        }
        catch
        {
            // Reset is best effort; a failed device is handled on the next frame.
        }
    }

    public void Dispose()
    {
        _driver?.Dispose();
        _driver = null;
    }
}
