using System.Buffers.Binary;
using MoTouchPad.Windows.Protocol;

const int headerSize = 24;
const int contactSize = 24;
var bytes = new byte[headerSize + contactSize];
BinaryPrimitives.WriteUInt32LittleEndian(bytes, 0x3150544D);
bytes[4] = 1;
bytes[5] = (byte)FrameType.Touch;
BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(8), 42);
BinaryPrimitives.WriteInt64LittleEndian(bytes.AsSpan(12), 123456789);
bytes[20] = 1;
bytes[21] = 0;
bytes[22] = 135;
bytes[23] = 1;

var contact = bytes.AsSpan(headerSize);
contact[0] = 7;
contact[1] = 1;
WriteSingle(contact[4..], 0.25f);
WriteSingle(contact[8..], 0.75f);
WriteSingle(contact[12..], 0.5f);
WriteSingle(contact[16..], 0.02f);
WriteSingle(contact[20..], 0.03f);

await using var stream = new MemoryStream(bytes);
var frame = await TouchFrame.ReadAsync(stream, CancellationToken.None);
Assert(frame.Sequence == 42, "sequence");
Assert(frame.TimestampNanos == 123456789, "timestamp");
Assert(frame.SensitivityPercent == 135, "sensitivity");
Assert(frame.NaturalScrolling, "natural scrolling");
Assert(frame.Contacts.Count == 1, "contact count");
Assert(frame.Contacts[0].Id == 7, "contact id");
Assert(frame.Contacts[0].Touching, "contact state");
Assert(Math.Abs(frame.Contacts[0].X - 0.25f) < 0.0001f, "x");
Assert(Math.Abs(frame.Contacts[0].Y - 0.75f) < 0.0001f, "y");

Console.WriteLine("MoTouchPad protocol smoke test passed.");

static void WriteSingle(Span<byte> target, float value)
{
    BinaryPrimitives.WriteInt32LittleEndian(
        target,
        BitConverter.SingleToInt32Bits(value));
}

static void Assert(bool condition, string name)
{
    if (!condition) throw new InvalidOperationException($"Assertion failed: {name}");
}
