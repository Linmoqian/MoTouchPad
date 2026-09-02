using System.Text.Json;
using MoTouchPad.Windows.Model;
using MoTouchPad.Windows.Protocol;

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

var repositoryRoot = FindRepositoryRoot();
var fixtureRoot = Path.Combine(repositoryRoot, "protocol", "fixtures");
var manifest = JsonSerializer.Deserialize<FixtureManifest>(
    await File.ReadAllTextAsync(Path.Combine(fixtureRoot, "manifest.json")),
    new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
    ?? throw new InvalidOperationException("Cannot read fixture manifest.");

foreach (var name in manifest.Valid)
{
    var bytes = await ReadHexAsync(Path.Combine(fixtureRoot, name));
    if (name == "stream-two-frames.hex")
    {
        await VerifyStreamAsync(bytes);
        continue;
    }

    var frame = TouchFrameCodec.Decode(bytes);
    Assert(bytes.SequenceEqual(TouchFrameCodec.Encode(frame)), $"{name}: canonical bytes");
}

foreach (var name in manifest.Invalid)
{
    var bytes = await ReadHexAsync(Path.Combine(fixtureRoot, name));
    try
    {
        TouchFrameCodec.Decode(bytes);
    }
    catch (InvalidDataException)
    {
        continue;
    }

    throw new InvalidOperationException($"{name}: invalid fixture was accepted.");
}

Console.WriteLine(
    $"Validated {manifest.Valid.Count} valid and {manifest.Invalid.Count} invalid protocol fixtures.");

static async Task VerifyStreamAsync(byte[] bytes)
{
    await using var stream = new ChunkedReadStream(bytes, maxRead: 3);
    var hello = await TouchFrameCodec.ReadAsync(stream, CancellationToken.None);
    var touch = await TouchFrameCodec.ReadAsync(stream, CancellationToken.None);
    Assert(hello.Type == FrameType.Hello, "stream hello");
    Assert(touch.Type == FrameType.Touch, "stream touch");
    Assert(touch.Contacts.Count == 1, "stream contact count");
}

static async Task<byte[]> ReadHexAsync(string path)
{
    var tokens = (await File.ReadAllTextAsync(path))
        .Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
    if (tokens.Any(token => token.Length != 2))
    {
        throw new InvalidOperationException($"{Path.GetFileName(path)}: invalid hex token.");
    }

    return tokens.Select(token => Convert.ToByte(token, 16)).ToArray();
}

static string FindRepositoryRoot()
{
    var directory = new DirectoryInfo(Directory.GetCurrentDirectory());
    while (directory is not null)
    {
        if (File.Exists(Path.Combine(directory.FullName, "protocol", "fixtures", "manifest.json")))
        {
            return directory.FullName;
        }

        directory = directory.Parent;
    }

    throw new DirectoryNotFoundException("Cannot locate repository root.");
}

static void Assert(bool condition, string name)
{
    if (!condition) throw new InvalidOperationException($"Assertion failed: {name}");
}

file sealed record FixtureManifest(List<string> Valid, List<string> Invalid);

file sealed class ChunkedReadStream(byte[] bytes, int maxRead) : MemoryStream(bytes)
{
    public override ValueTask<int> ReadAsync(
        Memory<byte> buffer,
        CancellationToken cancellationToken = default)
    {
        return base.ReadAsync(
            buffer[..Math.Min(buffer.Length, maxRead)],
            cancellationToken);
    }
}
