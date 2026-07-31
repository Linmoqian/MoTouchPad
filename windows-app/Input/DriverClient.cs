using System.Buffers.Binary;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
using MoTouchPad.Windows.Protocol;

namespace MoTouchPad.Windows.Input;

internal sealed class DriverClient : IDisposable
{
    private const string DevicePath = @"\\.\MoTouchPad";
    private const uint GenericWrite = 0x40000000;
    private const uint OpenExisting = 3;
    private const uint IoctlSubmitFrame = 0x22A000;
    private const int DriverFrameSize = 128;
    private const int DriverContactSize = 24;
    private readonly SafeFileHandle _handle;

    private DriverClient(SafeFileHandle handle)
    {
        _handle = handle;
    }

    public static DriverClient? TryOpen()
    {
        var handle = CreateFile(
            DevicePath,
            GenericWrite,
            0,
            IntPtr.Zero,
            OpenExisting,
            0,
            IntPtr.Zero);
        return handle.IsInvalid ? null : new DriverClient(handle);
    }

    public void Submit(TouchFrame frame)
    {
        Span<byte> buffer = stackalloc byte[DriverFrameSize];
        BinaryPrimitives.WriteUInt32LittleEndian(buffer, frame.Sequence);
        buffer[4] = (byte)Math.Min(5, frame.Contacts.Count);
        buffer[5] = frame.Buttons;

        for (var index = 0; index < buffer[4]; index++)
        {
            var contact = frame.Contacts[index];
            var target = buffer.Slice(8 + index * DriverContactSize, DriverContactSize);
            target[0] = contact.Id;
            // HID bit 0 is Confidence and bit 1 is Tip Switch. Keep the
            // contact confident while clearing Tip Switch for the up report.
            target[1] = contact.Touching ? (byte)0x03 : (byte)0x01;
            WriteNormalized(target[4..], contact.X);
            WriteNormalized(target[6..], contact.Y);
            WriteNormalized(target[8..], contact.Pressure);
            WriteNormalized(target[10..], contact.Major);
            WriteNormalized(target[12..], contact.Minor);
        }

        var managed = buffer.ToArray();
        if (!DeviceIoControl(
                _handle,
                IoctlSubmitFrame,
                managed,
                managed.Length,
                null,
                0,
                out _,
                IntPtr.Zero))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }
    }

    private static void WriteNormalized(Span<byte> target, float value)
    {
        var normalized = (ushort)Math.Round(Math.Clamp(value, 0f, 1f) * ushort.MaxValue);
        BinaryPrimitives.WriteUInt16LittleEndian(target, normalized);
    }

    public void Dispose() => _handle.Dispose();

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFile(
        string fileName,
        uint desiredAccess,
        uint shareMode,
        IntPtr securityAttributes,
        uint creationDisposition,
        uint flagsAndAttributes,
        IntPtr templateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DeviceIoControl(
        SafeFileHandle device,
        uint controlCode,
        byte[] input,
        int inputSize,
        byte[]? output,
        int outputSize,
        out int bytesReturned,
        IntPtr overlapped);
}
