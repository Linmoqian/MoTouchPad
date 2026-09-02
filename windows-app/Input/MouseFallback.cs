using System.Runtime.InteropServices;
using MoTouchPad.Windows.Model;

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

namespace MoTouchPad.Windows.Input;

internal sealed class MouseFallback
{
    private TouchContact? _previous;
    private DateTime _contactStarted;
    private float _travel;
    private float? _twoFingerX;
    private float? _twoFingerY;
    private float? _twoFingerDistance;
    private float _twoFingerScrollEvidence;
    private float _twoFingerPinchEvidence;
    private float _pinchWheelRemainder;
    private TwoFingerMode _twoFingerMode;
    private readonly Dictionary<byte, TouchContact> _twoFingerPrevious = [];
    private DateTime _twoFingerStarted;
    private float _twoFingerTravel;
    private bool _twoFingerGesture;
    private bool _suppressUntilRelease;

    public void Reset()
    {
        _previous = null;
        _contactStarted = default;
        _travel = 0;
        ResetTwoFingerGesture();
        _suppressUntilRelease = false;
    }

    public void Submit(TouchFrame frame, bool movePointer = true)
    {
        if (frame.Type != FrameType.Touch) return;
        var touching = frame.Contacts.Where(contact => contact.Touching).ToArray();
        if (_suppressUntilRelease)
        {
            if (touching.Length == 0) _suppressUntilRelease = false;
            return;
        }

        if (touching.Length > 2)
        {
            _previous = null;
            ResetTwoFingerGesture();
            _suppressUntilRelease = true;
            return;
        }

        if (touching.Length == 1)
        {
            if (_twoFingerGesture)
            {
                TrackTwoFingerTravel(frame.Contacts);
                return;
            }

            _twoFingerY = null;
            var contact = touching[0];
            if (_previous is null || _previous.Id != contact.Id)
            {
                _previous = contact;
                _contactStarted = DateTime.UtcNow;
                _travel = 0;
                return;
            }

            var deltaX = contact.X - _previous.X;
            var deltaY = contact.Y - _previous.Y;
            _travel += MathF.Abs(deltaX) + MathF.Abs(deltaY);
            if (movePointer) Move(deltaX, deltaY, frame.SensitivityPercent);
            _previous = contact;
            return;
        }

        if (touching.Length == 2)
        {
            _previous = null;
            if (!_twoFingerGesture)
            {
                _twoFingerGesture = true;
                _twoFingerStarted = DateTime.UtcNow;
                _twoFingerTravel = 0;
                _twoFingerScrollEvidence = 0;
                _twoFingerPinchEvidence = 0;
                _pinchWheelRemainder = 0;
                _twoFingerMode = TwoFingerMode.Undecided;
                _twoFingerPrevious.Clear();
            }
            TrackTwoFingerTravel(touching);

            var averageX = (touching[0].X + touching[1].X) / 2f;
            var averageY = (touching[0].Y + touching[1].Y) / 2f;
            var distanceX = touching[0].X - touching[1].X;
            var distanceY = touching[0].Y - touching[1].Y;
            var distance = MathF.Sqrt(distanceX * distanceX + distanceY * distanceY);
            if (_twoFingerX is { } previousX &&
                _twoFingerY is { } previousY &&
                _twoFingerDistance is { } previousDistance)
            {
                var centerDeltaX = averageX - previousX;
                var centerDeltaY = averageY - previousY;
                var centerDelta = MathF.Sqrt(
                    centerDeltaX * centerDeltaX + centerDeltaY * centerDeltaY);
                var distanceDelta = distance - previousDistance;
                _twoFingerScrollEvidence += centerDelta;
                _twoFingerPinchEvidence += MathF.Abs(distanceDelta);

                if (_twoFingerMode == TwoFingerMode.Undecided)
                {
                    if (_twoFingerPinchEvidence >= 0.008f &&
                        _twoFingerPinchEvidence > _twoFingerScrollEvidence * 1.1f)
                    {
                        _twoFingerMode = TwoFingerMode.Pinch;
                    }
                    else if (_twoFingerScrollEvidence >= 0.006f &&
                        _twoFingerScrollEvidence > _twoFingerPinchEvidence * 1.1f)
                    {
                        _twoFingerMode = TwoFingerMode.Scroll;
                    }
                }

                if (_twoFingerMode == TwoFingerMode.Pinch)
                {
                    _pinchWheelRemainder += distanceDelta * 4800f;
                    var wheelSteps = (int)(_pinchWheelRemainder / WheelDelta);
                    if (wheelSteps != 0)
                    {
                        var wheel = wheelSteps * WheelDelta;
                        _pinchWheelRemainder -= wheel;
                        SendZoomWheel(wheel);
                    }
                }
                else if (_twoFingerMode == TwoFingerMode.Scroll)
                {
                    var direction = frame.NaturalScrolling ? -1 : 1;
                    var wheel = (int)Math.Round((previousY - averageY) * 2400 * direction);
                    if (wheel != 0) SendMouse(0, 0, wheel, MouseEventWheel);
                }
            }
            _twoFingerX = averageX;
            _twoFingerY = averageY;
            _twoFingerDistance = distance;
            return;
        }

        if (_twoFingerGesture)
        {
            TrackTwoFingerTravel(frame.Contacts);
            var elapsed = DateTime.UtcNow - _twoFingerStarted;
            var hasRelease = frame.Contacts.Any(contact => !contact.Touching);
            if (hasRelease &&
                elapsed < TimeSpan.FromMilliseconds(320) &&
                _twoFingerTravel < 0.035f &&
                _twoFingerMode == TwoFingerMode.Undecided)
            {
                SendMouse(0, 0, 0, MouseEventRightDown);
                SendMouse(0, 0, 0, MouseEventRightUp);
            }
            ResetTwoFingerGesture();
            return;
        }

        var released = frame.Contacts.FirstOrDefault(contact => !contact.Touching);
        if (_previous is not null && released?.Id == _previous.Id)
        {
            var elapsed = DateTime.UtcNow - _contactStarted;
            if (elapsed < TimeSpan.FromMilliseconds(260) && _travel < 0.025f)
            {
                SendMouse(0, 0, 0, MouseEventLeftDown);
                SendMouse(0, 0, 0, MouseEventLeftUp);
            }
        }
        _previous = null;
        _twoFingerY = null;
    }

    private void TrackTwoFingerTravel(IEnumerable<TouchContact> contacts)
    {
        foreach (var contact in contacts)
        {
            if (_twoFingerPrevious.TryGetValue(contact.Id, out var previous))
            {
                _twoFingerTravel += MathF.Abs(contact.X - previous.X) +
                    MathF.Abs(contact.Y - previous.Y);
            }
            _twoFingerPrevious[contact.Id] = contact;
        }
    }

    private void ResetTwoFingerGesture()
    {
        _twoFingerGesture = false;
        _twoFingerX = null;
        _twoFingerY = null;
        _twoFingerDistance = null;
        _twoFingerScrollEvidence = 0;
        _twoFingerPinchEvidence = 0;
        _pinchWheelRemainder = 0;
        _twoFingerMode = TwoFingerMode.Undecided;
        _twoFingerPrevious.Clear();
    }

    private static void Move(float deltaX, float deltaY, byte sensitivityPercent)
    {
        var scale = 2200f * sensitivityPercent / 100f;
        var x = (int)Math.Round(deltaX * scale);
        var y = (int)Math.Round(deltaY * scale);
        if (x != 0 || y != 0) SendMouse(x, y, 0, MouseEventMove);
    }

    private static void SendMouse(int dx, int dy, int data, uint flags)
    {
        var input = new INPUT
        {
            type = 0,
            mouse = new MOUSEINPUT
            {
                dx = dx,
                dy = dy,
                mouseData = data,
                flags = flags
            }
        };
        SendInput(1, [input], Marshal.SizeOf<INPUT>());
    }

    private static void SendZoomWheel(int wheel)
    {
        keybd_event(VirtualKeyControl, 0, 0, UIntPtr.Zero);
        try
        {
            SendMouse(0, 0, wheel, MouseEventWheel);
        }
        finally
        {
            keybd_event(VirtualKeyControl, 0, KeyEventKeyUp, UIntPtr.Zero);
        }
    }

    private const uint MouseEventMove = 0x0001;
    private const uint MouseEventLeftDown = 0x0002;
    private const uint MouseEventLeftUp = 0x0004;
    private const uint MouseEventRightDown = 0x0008;
    private const uint MouseEventRightUp = 0x0010;
    private const uint MouseEventWheel = 0x0800;
    private const int WheelDelta = 120;
    private const byte VirtualKeyControl = 0x11;
    private const uint KeyEventKeyUp = 0x0002;

    private enum TwoFingerMode
    {
        Undecided,
        Scroll,
        Pinch
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public uint type;
        public MOUSEINPUT mouse;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public int mouseData;
        public uint flags;
        public uint time;
        public IntPtr extraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(
        uint inputCount,
        INPUT[] inputs,
        int inputSize);

    [DllImport("user32.dll")]
    private static extern void keybd_event(
        byte virtualKey,
        byte scanCode,
        uint flags,
        UIntPtr extraInfo);
}
