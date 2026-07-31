using System.Buffers.Binary;
using System.IO;

namespace MoTouchPad.Windows.Protocol;

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
    IReadOnlyList<TouchContact> Contacts)
{
    private const uint Magic = 0x3150544D;
    private const int HeaderSize = 24;
    private const int ContactSize = 24;
    private const int MaxContacts = 5;

    public static async ValueTask<TouchFrame> ReadAsync(
        Stream stream,
        CancellationToken cancellationToken)
    {
        var header = new byte[HeaderSize];
        await stream.ReadExactlyAsync(header, cancellationToken);
        if (BinaryPrimitives.ReadUInt32LittleEndian(header) != Magic)
        {
            throw new InvalidDataException("Invalid MoTouchPad frame magic.");
        }

        if (header[4] != 1)
        {
            throw new InvalidDataException($"Unsupported protocol version {header[4]}.");
        }

        var type = (FrameType)header[5];
        var sequence = BinaryPrimitives.ReadUInt32LittleEndian(header.AsSpan(8));
        var timestamp = BinaryPrimitives.ReadInt64LittleEndian(header.AsSpan(12));
        var count = header[20];
        var buttons = header[21];
        var sensitivityPercent = header[22] == 0
            ? (byte)100
            : (byte)Math.Clamp((int)header[22], 50, 200);
        var naturalScrolling = (header[23] & 0x01) != 0;
        if (count > MaxContacts)
        {
            throw new InvalidDataException($"Invalid contact count {count}.");
        }

        var payload = new byte[count * ContactSize];
        if (payload.Length > 0)
        {
            await stream.ReadExactlyAsync(payload, cancellationToken);
        }

        var contacts = new List<TouchContact>(count);
        for (var index = 0; index < count; index++)
        {
            var contact = payload.AsSpan(index * ContactSize, ContactSize);
            contacts.Add(new TouchContact(
                contact[0],
                contact[1] != 0,
                ReadSingle(contact[4..]),
                ReadSingle(contact[8..]),
                ReadSingle(contact[12..]),
                ReadSingle(contact[16..]),
                ReadSingle(contact[20..])));
        }

        return new TouchFrame(
            type,
            sequence,
            timestamp,
            buttons,
            sensitivityPercent,
            naturalScrolling,
            contacts);
    }

    private static float ReadSingle(ReadOnlySpan<byte> bytes)
    {
        var bits = BinaryPrimitives.ReadInt32LittleEndian(bytes);
        return BitConverter.Int32BitsToSingle(bits);
    }
}
