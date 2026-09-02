using System.Buffers.Binary;
using System.IO;
using MoTouchPad.Windows.Model;

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

namespace MoTouchPad.Windows.Protocol;

internal static class TouchFrameCodec
{
    internal const int Port = 47651;
    internal const uint Magic = 0x3150544D;
    internal const int HeaderSize = 24;
    internal const int ContactSize = 24;
    internal const int MaxContacts = 5;

    public static async ValueTask<TouchFrame> ReadAsync(
        Stream stream,
        CancellationToken cancellationToken)
    {
        var header = new byte[HeaderSize];
        await stream.ReadExactlyAsync(header, cancellationToken);
        var count = header[20];
        if (count > MaxContacts)
        {
            throw new InvalidDataException($"Invalid contact count {count}.");
        }

        var payload = new byte[count * ContactSize];
        if (payload.Length > 0)
        {
            await stream.ReadExactlyAsync(payload, cancellationToken);
        }

        var frameBytes = new byte[HeaderSize + payload.Length];
        header.CopyTo(frameBytes, 0);
        payload.CopyTo(frameBytes, HeaderSize);
        return Decode(frameBytes);
    }

    public static TouchFrame Decode(ReadOnlySpan<byte> bytes)
    {
        if (bytes.Length < HeaderSize)
        {
            throw new InvalidDataException("Frame is shorter than header.");
        }

        if (BinaryPrimitives.ReadUInt32LittleEndian(bytes) != Magic)
        {
            throw new InvalidDataException("Invalid MoTouchPad frame magic.");
        }

        if (bytes[4] != 1)
        {
            throw new InvalidDataException($"Unsupported protocol version {bytes[4]}.");
        }

        var type = bytes[5] switch
        {
            1 => FrameType.Hello,
            2 => FrameType.Touch,
            _ => throw new InvalidDataException($"Unsupported frame type {bytes[5]}.")
        };
        if (BinaryPrimitives.ReadUInt16LittleEndian(bytes[6..]) != 0)
        {
            throw new InvalidDataException("Reserved header flags must be zero.");
        }
        var count = bytes[20];
        if (count > MaxContacts)
        {
            throw new InvalidDataException($"Invalid contact count {count}.");
        }

        var expectedLength = HeaderSize + count * ContactSize;
        if (bytes.Length != expectedLength)
        {
            throw new InvalidDataException($"Invalid frame length {bytes.Length}.");
        }

        if (type == FrameType.Hello && count != 0)
        {
            throw new InvalidDataException("Hello frame must not contain contacts.");
        }

        var sensitivityRaw = bytes[22];
        if (sensitivityRaw != 0 && sensitivityRaw is < 50 or > 200)
        {
            throw new InvalidDataException($"Invalid sensitivity {sensitivityRaw}.");
        }

        var contacts = new List<TouchContact>(count);
        for (var index = 0; index < count; index++)
        {
            var offset = HeaderSize + index * ContactSize;
            var contact = new TouchContact(
                bytes[offset],
                ReadContactState(bytes[offset + 1]),
                ReadSingle(bytes[(offset + 4)..]),
                ReadSingle(bytes[(offset + 8)..]),
                ReadSingle(bytes[(offset + 12)..]),
                ReadSingle(bytes[(offset + 16)..]),
                ReadSingle(bytes[(offset + 20)..]));
            if (BinaryPrimitives.ReadUInt16LittleEndian(bytes[(offset + 2)..]) != 0)
            {
                throw new InvalidDataException("Reserved contact bytes must be zero.");
            }
            ValidateContact(contact);
            contacts.Add(contact);
        }

        return new TouchFrame(
            type,
            BinaryPrimitives.ReadUInt32LittleEndian(bytes[8..]),
            BinaryPrimitives.ReadInt64LittleEndian(bytes[12..]),
            bytes[21],
            sensitivityRaw == 0 ? (byte)100 : sensitivityRaw,
            ReadSettingsFlags(bytes[23]),
            contacts);
    }

    public static byte[] Encode(TouchFrame frame)
    {
        if (frame.Contacts.Count > MaxContacts)
        {
            throw new InvalidDataException($"Too many contacts: {frame.Contacts.Count}.");
        }

        if (frame.Type == FrameType.Hello && frame.Contacts.Count != 0)
        {
            throw new InvalidDataException("Hello frame must not contain contacts.");
        }

        if (frame.SensitivityPercent != 0 && frame.SensitivityPercent is < 50 or > 200)
        {
            throw new InvalidDataException($"Invalid sensitivity {frame.SensitivityPercent}.");
        }

        var bytes = new byte[HeaderSize + frame.Contacts.Count * ContactSize];
        BinaryPrimitives.WriteUInt32LittleEndian(bytes, Magic);
        bytes[4] = 1;
        bytes[5] = (byte)frame.Type;
        BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(8), frame.Sequence);
        BinaryPrimitives.WriteInt64LittleEndian(bytes.AsSpan(12), frame.TimestampNanos);
        bytes[20] = (byte)frame.Contacts.Count;
        bytes[21] = frame.Buttons;
        bytes[22] = frame.SensitivityPercent == 0 ? (byte)100 : frame.SensitivityPercent;
        bytes[23] = frame.NaturalScrolling ? (byte)1 : (byte)0;

        for (var index = 0; index < frame.Contacts.Count; index++)
        {
            var contact = frame.Contacts[index];
            ValidateContact(contact);
            var offset = HeaderSize + index * ContactSize;
            bytes[offset] = contact.Id;
            bytes[offset + 1] = contact.Touching ? (byte)1 : (byte)0;
            WriteSingle(bytes.AsSpan(offset + 4), contact.X);
            WriteSingle(bytes.AsSpan(offset + 8), contact.Y);
            WriteSingle(bytes.AsSpan(offset + 12), contact.Pressure);
            WriteSingle(bytes.AsSpan(offset + 16), contact.Major);
            WriteSingle(bytes.AsSpan(offset + 20), contact.Minor);
        }
        return bytes;
    }

    private static bool ReadContactState(byte value)
    {
        return value switch
        {
            0 => false,
            1 => true,
            _ => throw new InvalidDataException($"Invalid contact state {value}.")
        };
    }

    private static bool ReadSettingsFlags(byte value)
    {
        if ((value & 0xFE) != 0)
        {
            throw new InvalidDataException("Unknown settings flags.");
        }
        return (value & 0x01) != 0;
    }

    private static float ReadSingle(ReadOnlySpan<byte> bytes)
    {
        return BitConverter.Int32BitsToSingle(
            BinaryPrimitives.ReadInt32LittleEndian(bytes));
    }

    private static void WriteSingle(Span<byte> bytes, float value)
    {
        BinaryPrimitives.WriteInt32LittleEndian(
            bytes,
            BitConverter.SingleToInt32Bits(value));
    }

    private static void ValidateContact(TouchContact contact)
    {
        var values = new[] { contact.X, contact.Y, contact.Pressure, contact.Major, contact.Minor };
        if (values.Any(value => !float.IsFinite(value) || value is < 0f or > 1f))
        {
            throw new InvalidDataException("Contact values must be finite and normalized.");
        }
    }
}
