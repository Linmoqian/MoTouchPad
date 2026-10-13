using System.Net.Sockets;
using MoTouchPad.Windows.Model;
using MoTouchPad.Windows.Protocol;

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

namespace MoTouchPad.Windows.Transport;

internal sealed class TcpTouchReceiver
{
    private static readonly byte[] Heartbeat = [0x7F];

    public async Task ReceiveAsync(
        TcpClient client,
        Action<TouchFrame> onFrame,
        CancellationToken cancellationToken)
    {
        client.NoDelay = true;
        await using var stream = client.GetStream();
        using var heartbeatCancellation =
            CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        var heartbeatTask = SendHeartbeatsAsync(stream, heartbeatCancellation.Token);

        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                var frame = await TouchFrameCodec.ReadAsync(stream, cancellationToken);
                onFrame(frame);
            }
        }
        finally
        {
            heartbeatCancellation.Cancel();
            try
            {
                await heartbeatTask;
            }
            catch (OperationCanceledException)
            {
                // Normal connection shutdown.
            }
            catch (IOException)
            {
                // The peer may close its receive side while the heartbeat is writing.
            }
        }
    }

    private static async Task SendHeartbeatsAsync(
        NetworkStream stream,
        CancellationToken cancellationToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(1));
        while (await timer.WaitForNextTickAsync(cancellationToken))
        {
            await stream.WriteAsync(Heartbeat, cancellationToken);
            await stream.FlushAsync(cancellationToken);
        }
    }
}
