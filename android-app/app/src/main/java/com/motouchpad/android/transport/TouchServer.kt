package com.motouchpad.android.transport

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

import android.os.SystemClock
import android.util.Log
import android.view.MotionEvent
import com.motouchpad.android.model.FrameType
import com.motouchpad.android.model.TouchContact
import com.motouchpad.android.model.TouchFrame
import com.motouchpad.android.protocol.TouchFrameCodec
import com.motouchpad.android.protocol.TouchProtocol
import java.io.BufferedOutputStream
import java.io.Closeable
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread
import kotlin.math.max

class TouchServer(private val statusChanged: () -> Unit) : Closeable {
    companion object {
        const val PORT = TouchProtocol.PORT
        private const val LOG_TAG = "MoTouchPad"
    }

    private val running = AtomicBoolean(false)
    private val sequence = AtomicInteger()
    private val outputLock = Any()
    private val outbound = LinkedBlockingQueue<ByteArray>(256)
    private var serverSocket: ServerSocket? = null
    private var client: Socket? = null
    private var output: BufferedOutputStream? = null

    @Volatile
    var connected: Boolean = false
        private set

    @Volatile
    var connectionType: ConnectionType = ConnectionType.NONE
        private set

    @Volatile
    private var sensitivityPercent = 100

    @Volatile
    private var naturalScrolling = false

    fun updateSettings(sensitivity: Int, natural: Boolean) {
        sensitivityPercent = sensitivity.coerceIn(50, 200)
        naturalScrolling = natural
    }

    fun start() {
        if (!running.compareAndSet(false, true)) return
        thread(name = "MoTouchPad-sender", isDaemon = true) {
            while (running.get()) {
                val packet = outbound.poll(500, TimeUnit.MILLISECONDS) ?: continue
                synchronized(outputLock) {
                    try {
                        output?.apply {
                            write(packet)
                            flush()
                        }
                    } catch (exception: Exception) {
                        Log.e(LOG_TAG, "Touch frame write failed", exception)
                        clearClient(client)
                    }
                }
            }
        }
        thread(name = "MoTouchPad-server", isDaemon = true) {
            try {
                ServerSocket().use { server ->
                    server.reuseAddress = true
                    server.bind(InetSocketAddress(PORT))
                    serverSocket = server
                    while (running.get()) {
                        val socket = server.accept()
                        Log.i(LOG_TAG, "Accepted client ${socket.remoteSocketAddress}")
                        socket.tcpNoDelay = true
                        replaceClient(socket)
                        thread(name = "MoTouchPad-heartbeat", isDaemon = true) {
                            watchHeartbeats(socket)
                        }
                    }
                }
            } catch (exception: Exception) {
                if (running.get()) Log.e(LOG_TAG, "Touch server stopped", exception)
                setConnection(false, ConnectionType.NONE)
            }
        }
    }

    private fun watchHeartbeats(socket: Socket) {
        try {
            val input = socket.getInputStream()
            while (running.get() && !socket.isClosed) {
                val value = input.read()
                if (value < 0) {
                    Log.w(LOG_TAG, "Client input reached EOF")
                    break
                }
                if (value != TouchProtocol.HEARTBEAT) {
                    Log.w(LOG_TAG, "Unexpected control byte: $value")
                    break
                }
            }
        } catch (exception: Exception) {
            if (running.get()) Log.w(LOG_TAG, "Heartbeat reader stopped", exception)
        } finally {
            clearClient(socket)
        }
    }

    fun send(event: MotionEvent, surfaceWidth: Int, surfaceHeight: Int) {
        if (!connected) return
        val actionIndex = event.actionIndex
        val action = event.actionMasked
        if (action == MotionEvent.ACTION_CANCEL) {
            sendSnapshot(emptyList())
            return
        }

        val contacts = buildList {
            for (index in 0 until minOf(event.pointerCount, TouchProtocol.MAX_CONTACTS)) {
                val released = (action == MotionEvent.ACTION_UP ||
                    action == MotionEvent.ACTION_POINTER_UP) && index == actionIndex
                add(
                    TouchContact(
                        id = event.getPointerId(index),
                        touching = !released,
                        x = (event.getX(index) / max(1, surfaceWidth)).coerceIn(0f, 1f),
                        y = (event.getY(index) / max(1, surfaceHeight)).coerceIn(0f, 1f),
                        pressure = event.getPressure(index).coerceIn(0f, 1f),
                        major = (event.getTouchMajor(index) / max(1, surfaceWidth))
                            .coerceIn(0f, 1f),
                        minor = (event.getTouchMinor(index) / max(1, surfaceHeight))
                            .coerceIn(0f, 1f)
                    )
                )
            }
        }
        sendSnapshot(contacts)

        if (action == MotionEvent.ACTION_UP) {
            sendSnapshot(emptyList())
        } else if (action == MotionEvent.ACTION_POINTER_UP) {
            sendSnapshot(contacts.filter { it.touching })
        }
    }

    private fun sendSnapshot(contacts: List<TouchContact>, type: FrameType = FrameType.TOUCH) {
        enqueue(
            TouchFrameCodec.encode(
                TouchFrame(
                    type = type,
                    sequence = sequence.incrementAndGet().toLong(),
                    timestampNanos = SystemClock.elapsedRealtimeNanos(),
                    buttons = 0,
                    sensitivityPercent = sensitivityPercent,
                    naturalScrolling = naturalScrolling,
                    contacts = contacts
                )
            )
        )
    }

    private fun enqueue(packet: ByteArray) {
        if (!outbound.offer(packet)) {
            outbound.poll()
            outbound.offer(packet)
            Log.w(LOG_TAG, "Outbound queue full; dropped oldest snapshot")
        }
    }

    private fun replaceClient(socket: Socket) {
        synchronized(outputLock) {
            client?.close()
            outbound.clear()
            client = socket
            output = BufferedOutputStream(socket.getOutputStream(), 8192)
            val type = if (socket.inetAddress.isLoopbackAddress) {
                ConnectionType.USB
            } else {
                ConnectionType.WIFI
            }
            setConnection(true, type)
            Log.i(LOG_TAG, "Sending protocol hello over $type")
            sendSnapshot(emptyList(), FrameType.HELLO)
        }
    }

    private fun clearClient(expected: Socket?) {
        synchronized(outputLock) {
            if (expected != null && client !== expected) return
            try {
                client?.close()
            } catch (_: Exception) {
                // Connection is already gone.
            }
            client = null
            output = null
            outbound.clear()
            setConnection(false, ConnectionType.NONE)
            Log.i(LOG_TAG, "Client cleared")
        }
    }

    private fun setConnection(value: Boolean, type: ConnectionType) {
        if (connected == value && connectionType == type) return
        connected = value
        connectionType = type
        statusChanged()
    }

    override fun close() {
        running.set(false)
        clearClient(null)
        try {
            serverSocket?.close()
        } catch (_: Exception) {
            // Server is already stopped.
        }
    }
}
