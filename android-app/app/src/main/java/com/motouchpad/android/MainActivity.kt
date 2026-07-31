package com.motouchpad.android

import android.app.Activity
import android.app.Dialog
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.SeekBar
import android.widget.Switch
import android.widget.TextView
import java.io.BufferedOutputStream
import java.io.Closeable
import java.net.Inet4Address
import java.net.ServerSocket
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

private const val PORT = 47651
private const val MAGIC = 0x3150544D
private const val VERSION: Byte = 1
private const val TYPE_HELLO: Byte = 1
private const val TYPE_TOUCH: Byte = 2
private const val MAX_CONTACTS = 5
private const val HEADER_SIZE = 24
private const val CONTACT_SIZE = 24
private const val LOG_TAG = "MoTouchPad"

class MainActivity : Activity() {
    private lateinit var touchSurface: TouchSurfaceView
    private val preferences by lazy {
        getSharedPreferences("touchpad_settings", Context.MODE_PRIVATE)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        touchSurface = TouchSurfaceView()
        setContentView(touchSurface)
        enterImmersiveMode()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) enterImmersiveMode()
    }

    override fun onDestroy() {
        touchSurface.close()
        super.onDestroy()
    }

    private fun enterImmersiveMode() {
        if (android.os.Build.VERSION.SDK_INT >= 30) {
            window.setDecorFitsSystemWindows(false)
            window.insetsController?.apply {
                hide(WindowInsets.Type.systemBars())
                systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility =
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                    View.SYSTEM_UI_FLAG_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                    View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        }
    }

    private inner class TouchSurfaceView : View(this), Closeable {
        private val density = resources.displayMetrics.density
        private val islandPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(25, 31, 42)
        }
        private val buttonPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(25, 31, 42)
        }
        private val titlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(239, 244, 252)
            textSize = dp(16f)
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        private val detailPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(148, 163, 184)
            textSize = dp(12f)
        }
        private val hintPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(81, 94, 113)
            textSize = dp(15f)
            textAlign = Paint.Align.CENTER
        }
        private val iconPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(215, 226, 241)
            style = Paint.Style.STROKE
            strokeWidth = dp(2f)
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        private val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val settingsBounds = RectF()
        private var settingsGesture = false
        private var sensitivityPercent = preferences.getInt("sensitivity", 100)
            .coerceIn(50, 200)
        private var naturalScrolling = preferences.getBoolean("natural_scrolling", false)
        private val server = TouchServer { postInvalidate() }

        init {
            isFocusable = true
            server.updateSettings(sensitivityPercent, naturalScrolling)
            server.start()
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            canvas.drawColor(Color.rgb(10, 14, 21))
            drawStatusIsland(canvas)

            hintPaint.textSize = dp(15f)
            canvas.drawText("整块屏幕均可触控", width / 2f, height / 2f, hintPaint)
            hintPaint.textSize = dp(12f)
            canvas.drawText(
                "单指移动与轻触  ·  双指滚动、缩放与轻触右击",
                width / 2f,
                height / 2f + dp(30f),
                hintPaint
            )
        }

        private fun drawStatusIsland(canvas: Canvas) {
            val top = dp(18f)
            val islandHeight = dp(66f)
            val buttonSize = islandHeight
            val gap = dp(12f)
            val islandWidth = min(width * 0.58f, dp(510f))
            val groupWidth = islandWidth + gap + buttonSize
            val left = (width - groupWidth) / 2f
            val island = RectF(left, top, left + islandWidth, top + islandHeight)
            settingsBounds.set(
                island.right + gap,
                top,
                island.right + gap + buttonSize,
                top + islandHeight
            )

            canvas.drawRoundRect(island, islandHeight / 2f, islandHeight / 2f, islandPaint)
            canvas.drawOval(settingsBounds, buttonPaint)

            val centerY = island.centerY()
            val dotX = island.left + dp(35f)
            dotPaint.color = if (server.connected) {
                Color.rgb(80, 220, 148)
            } else {
                Color.rgb(255, 177, 66)
            }
            canvas.drawCircle(dotX, centerY, dp(4f), dotPaint)

            val textLeft = island.left + dp(56f)
            val status = if (server.connected) "已连接" else "等待电脑连接"
            canvas.drawText(status, textLeft, centerY - dp(4f), titlePaint)
            val detail = when (server.connectionType) {
                ConnectionType.USB -> "USB 连接"
                ConnectionType.WIFI -> "Wi-Fi 连接"
                ConnectionType.NONE -> "${wifiIpv4Address(this@MainActivity)}:$PORT"
            }
            canvas.drawText(detail, textLeft, centerY + dp(18f), detailPaint)

            val typeIconX = island.right - dp(34f)
            when (server.connectionType) {
                ConnectionType.USB -> drawUsbIcon(canvas, typeIconX, centerY)
                ConnectionType.WIFI -> drawWifiIcon(canvas, typeIconX, centerY)
                ConnectionType.NONE -> drawLinkIcon(canvas, typeIconX, centerY)
            }
            drawSettingsIcon(canvas, settingsBounds.centerX(), settingsBounds.centerY())
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    settingsGesture = settingsBounds.contains(event.x, event.y)
                    if (!settingsGesture) server.send(event, width, height)
                }
                MotionEvent.ACTION_UP -> {
                    if (settingsGesture) {
                        if (settingsBounds.contains(event.x, event.y)) {
                            performClick()
                            showSettingsDialog()
                        }
                        settingsGesture = false
                    } else {
                        server.send(event, width, height)
                        performClick()
                    }
                }
                MotionEvent.ACTION_CANCEL -> {
                    if (!settingsGesture) server.send(event, width, height)
                    settingsGesture = false
                }
                else -> if (!settingsGesture) server.send(event, width, height)
            }
            return true
        }

        override fun performClick(): Boolean {
            super.performClick()
            return true
        }

        @Suppress("SetTextI18n", "UseSwitchCompatOrMaterialCode")
        private fun showSettingsDialog() {
            val dialog = Dialog(this@MainActivity)
            val panel = LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dpInt(28f), dpInt(24f), dpInt(28f), dpInt(22f))
                background = roundedBackground(Color.rgb(24, 30, 41), dp(28f))
            }

            panel.addView(label("触控板设置", 22f, Color.rgb(241, 245, 252), true))
            panel.addView(label("当前 Wi-Fi 地址", 12f, Color.rgb(139, 153, 174)).apply {
                setPadding(0, dpInt(22f), 0, dpInt(4f))
            })
            panel.addView(
                label(
                    "${wifiIpv4Address(this@MainActivity)}:$PORT",
                    17f,
                    Color.rgb(100, 189, 255),
                    true
                )
            )

            val sensitivityValue = label(
                "$sensitivityPercent%",
                14f,
                Color.rgb(100, 189, 255),
                true
            ).apply { gravity = Gravity.END }
            val sensitivityRow = LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(0, dpInt(24f), 0, 0)
                addView(
                    label("指针灵敏度", 16f, Color.rgb(232, 238, 247), true),
                    LinearLayout.LayoutParams(
                        0,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                        1f
                    )
                )
                addView(sensitivityValue)
            }
            panel.addView(sensitivityRow)
            panel.addView(SeekBar(this@MainActivity).apply {
                max = 150
                progress = sensitivityPercent - 50
                setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                    override fun onProgressChanged(
                        seekBar: SeekBar?,
                        progress: Int,
                        fromUser: Boolean
                    ) {
                        sensitivityPercent = progress + 50
                        sensitivityValue.text = "$sensitivityPercent%"
                        saveSettings()
                    }

                    override fun onStartTrackingTouch(seekBar: SeekBar?) = Unit
                    override fun onStopTrackingTouch(seekBar: SeekBar?) = Unit
                })
            })
            panel.addView(LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.HORIZONTAL
                addView(
                    label("50%", 11f, Color.rgb(112, 126, 147)),
                    LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                )
                addView(label("200%", 11f, Color.rgb(112, 126, 147)).apply {
                    gravity = Gravity.END
                })
            })

            panel.addView(Switch(this@MainActivity).apply {
                text = "自然滚动"
                textSize = 16f
                setTextColor(Color.rgb(232, 238, 247))
                gravity = Gravity.CENTER_VERTICAL
                isChecked = naturalScrolling
                setPadding(0, dpInt(22f), 0, 0)
                setOnCheckedChangeListener { _, checked ->
                    naturalScrolling = checked
                    saveSettings()
                }
            })
            panel.addView(label(
                "开启后，双指向下滑动会向上翻页",
                12f,
                Color.rgb(139, 153, 174)
            ).apply { setPadding(0, dpInt(4f), 0, 0) })

            panel.addView(Button(this@MainActivity).apply {
                text = "完成"
                isAllCaps = false
                textSize = 15f
                setTextColor(Color.WHITE)
                background = roundedBackground(Color.rgb(45, 126, 247), dp(18f))
                setOnClickListener { dialog.dismiss() }
            }, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dpInt(48f)
            ).apply { topMargin = dpInt(24f) })

            dialog.setContentView(panel)
            dialog.window?.apply {
                setBackgroundDrawableResource(android.R.color.transparent)
                addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
                attributes = attributes.apply { dimAmount = 0.55f }
            }
            dialog.setOnShowListener {
                dialog.window?.setLayout(
                    min(dpInt(480f), this@TouchSurfaceView.width - dpInt(48f)),
                    WindowManager.LayoutParams.WRAP_CONTENT
                )
            }
            dialog.show()
        }

        private fun saveSettings() {
            preferences.edit()
                .putInt("sensitivity", sensitivityPercent)
                .putBoolean("natural_scrolling", naturalScrolling)
                .apply()
            server.updateSettings(sensitivityPercent, naturalScrolling)
        }

        private fun label(textValue: String, size: Float, color: Int, bold: Boolean = false) =
            TextView(this@MainActivity).apply {
                text = textValue
                textSize = size
                setTextColor(color)
                if (bold) typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            }

        private fun roundedBackground(color: Int, radius: Float) = GradientDrawable().apply {
            setColor(color)
            cornerRadius = radius
        }

        private fun drawWifiIcon(canvas: Canvas, x: Float, y: Float) {
            val bounds = RectF(x - dp(12f), y - dp(12f), x + dp(12f), y + dp(12f))
            canvas.drawArc(bounds, 220f, 100f, false, iconPaint)
            bounds.inset(dp(5f), dp(5f))
            canvas.drawArc(bounds, 220f, 100f, false, iconPaint)
            canvas.drawCircle(x, y + dp(7f), dp(1.7f), iconPaint)
        }

        private fun drawUsbIcon(canvas: Canvas, x: Float, y: Float) {
            canvas.drawLine(x, y + dp(10f), x, y - dp(10f), iconPaint)
            canvas.drawLine(x, y - dp(10f), x - dp(4f), y - dp(6f), iconPaint)
            canvas.drawLine(x, y - dp(10f), x + dp(4f), y - dp(6f), iconPaint)
            canvas.drawLine(x, y, x - dp(7f), y - dp(4f), iconPaint)
            canvas.drawCircle(x - dp(8f), y - dp(5f), dp(2f), iconPaint)
            canvas.drawLine(x, y + dp(5f), x + dp(7f), y + dp(1f), iconPaint)
            canvas.drawRect(x + dp(6f), y - dp(2f), x + dp(10f), y + dp(2f), iconPaint)
        }

        private fun drawLinkIcon(canvas: Canvas, x: Float, y: Float) {
            canvas.drawCircle(x - dp(5f), y, dp(6f), iconPaint)
            canvas.drawCircle(x + dp(5f), y, dp(6f), iconPaint)
        }

        private fun drawSettingsIcon(canvas: Canvas, x: Float, y: Float) {
            canvas.drawCircle(x, y, dp(7f), iconPaint)
            canvas.drawCircle(x, y, dp(2f), iconPaint)
            repeat(8) { index ->
                val angle = Math.toRadians(index * 45.0)
                val innerX = x + cos(angle).toFloat() * dp(9f)
                val innerY = y + sin(angle).toFloat() * dp(9f)
                val outerX = x + cos(angle).toFloat() * dp(12f)
                val outerY = y + sin(angle).toFloat() * dp(12f)
                canvas.drawLine(innerX, innerY, outerX, outerY, iconPaint)
            }
        }

        private fun dp(value: Float) = value * density
        private fun dpInt(value: Float) = dp(value).toInt()

        override fun close() = server.close()
    }
}

private enum class ConnectionType {
    NONE,
    USB,
    WIFI
}

private class TouchServer(private val statusChanged: () -> Unit) : Closeable {
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
                ServerSocket(PORT).use { server ->
                    server.reuseAddress = true
                    serverSocket = server
                    while (running.get()) {
                        val socket = server.accept()
                        Log.i(LOG_TAG, "Accepted client ${socket.remoteSocketAddress}")
                        socket.tcpNoDelay = true
                        replaceClient(socket)
                        while (running.get() && !socket.isClosed) {
                            try {
                                if (socket.getInputStream().read() < 0) {
                                    Log.w(LOG_TAG, "Client input reached EOF")
                                    break
                                }
                            } catch (exception: Exception) {
                                Log.e(LOG_TAG, "Client input failed", exception)
                                break
                            }
                        }
                        clearClient(socket)
                    }
                }
            } catch (exception: Exception) {
                if (running.get()) Log.e(LOG_TAG, "Touch server stopped", exception)
                setConnection(false, ConnectionType.NONE)
            }
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
            for (index in 0 until minOf(event.pointerCount, MAX_CONTACTS)) {
                val released = (action == MotionEvent.ACTION_UP ||
                    action == MotionEvent.ACTION_POINTER_UP) && index == actionIndex
                add(
                    Contact(
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

    private fun sendSnapshot(contacts: List<Contact>, type: Byte = TYPE_TOUCH) {
        val buffer = ByteBuffer
            .allocate(HEADER_SIZE + contacts.size * CONTACT_SIZE)
            .order(ByteOrder.LITTLE_ENDIAN)
        buffer.putInt(MAGIC)
        buffer.put(VERSION)
        buffer.put(type)
        buffer.putShort(0)
        buffer.putInt(sequence.incrementAndGet())
        buffer.putLong(SystemClock.elapsedRealtimeNanos())
        buffer.put(contacts.size.toByte())
        buffer.put(0)
        buffer.put(sensitivityPercent.toByte())
        buffer.put(if (naturalScrolling) 1 else 0)
        for (contact in contacts) {
            buffer.put(contact.id.toByte())
            buffer.put(if (contact.touching) 1 else 0)
            buffer.putShort(0)
            buffer.putFloat(contact.x)
            buffer.putFloat(contact.y)
            buffer.putFloat(contact.pressure)
            buffer.putFloat(contact.major)
            buffer.putFloat(contact.minor)
        }

        val packet = buffer.array()
        if (!outbound.offer(packet)) {
            // Every packet is a complete snapshot, so preserving recency is safe.
            outbound.poll()
            outbound.offer(packet)
            Log.w(LOG_TAG, "Outbound queue full; dropped oldest snapshot")
        }
    }

    private fun replaceClient(socket: Socket) {
        synchronized(outputLock) {
            client?.close()
            client = socket
            output = BufferedOutputStream(socket.getOutputStream(), 8192)
            val type = if (socket.inetAddress.isLoopbackAddress) {
                ConnectionType.USB
            } else {
                ConnectionType.WIFI
            }
            setConnection(true, type)
            Log.i(LOG_TAG, "Sending protocol hello over $type")
            sendSnapshot(emptyList(), TYPE_HELLO)
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
        clearClient(client)
        try {
            serverSocket?.close()
        } catch (_: Exception) {
            // Server is already stopped.
        }
    }
}

private data class Contact(
    val id: Int,
    val touching: Boolean,
    val x: Float,
    val y: Float,
    val pressure: Float,
    val major: Float,
    val minor: Float
)

private fun wifiIpv4Address(context: Context): String {
    return try {
        val connectivity = context.getSystemService(ConnectivityManager::class.java)
        val network = connectivity.activeNetwork ?: return "Wi-Fi 未连接"
        val capabilities = connectivity.getNetworkCapabilities(network)
        if (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) != true) {
            return "Wi-Fi 未连接"
        }
        connectivity.getLinkProperties(network)
            ?.linkAddresses
            ?.firstOrNull { it.address is Inet4Address && !it.address.isLoopbackAddress }
            ?.address
            ?.hostAddress
            ?: "Wi-Fi 未连接"
    } catch (_: Exception) {
        "Wi-Fi 未连接"
    }
}
