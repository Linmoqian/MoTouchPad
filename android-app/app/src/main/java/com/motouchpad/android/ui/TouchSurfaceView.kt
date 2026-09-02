package com.motouchpad.android.ui

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

import android.app.Activity
import android.app.Dialog
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.SeekBar
import android.widget.Switch
import android.widget.TextView
import com.motouchpad.android.model.TouchpadSettings
import com.motouchpad.android.settings.TouchpadSettingsStore
import com.motouchpad.android.transport.ConnectionType
import com.motouchpad.android.transport.TouchServer
import com.motouchpad.android.transport.wifiIpv4Address
import java.io.Closeable
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

class TouchSurfaceView(context: Context) : View(context), Closeable {
    private val activity = context as Activity
    private val density = resources.displayMetrics.density
    private val settingsStore = TouchpadSettingsStore(context)
    private var sensitivityPercent = settingsStore.load().sensitivityPercent
    private var naturalScrolling = settingsStore.load().naturalScrolling
    private var wifiAddress = wifiIpv4Address(context)

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
            ConnectionType.NONE -> "$wifiAddress:${TouchServer.PORT}"
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
        wifiAddress = wifiIpv4Address(context)
        val dialog = Dialog(activity)
        val panel = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dpInt(28f), dpInt(24f), dpInt(28f), dpInt(22f))
            background = roundedBackground(Color.rgb(24, 30, 41), dp(28f))
        }

        panel.addView(label("触控板设置", 22f, Color.rgb(241, 245, 252), true))
        panel.addView(label("当前 Wi-Fi 地址", 12f, Color.rgb(139, 153, 174)).apply {
            setPadding(0, dpInt(22f), 0, dpInt(4f))
        })
        panel.addView(label(
            "$wifiAddress:${TouchServer.PORT}",
            17f,
            Color.rgb(100, 189, 255),
            true
        ))

        val sensitivityValue = label(
            "$sensitivityPercent%",
            14f,
            Color.rgb(100, 189, 255),
            true
        ).apply { gravity = Gravity.END }
        val sensitivityRow = LinearLayout(activity).apply {
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
        panel.addView(SeekBar(activity).apply {
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
        panel.addView(LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            addView(
                label("50%", 11f, Color.rgb(112, 126, 147)),
                LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            )
            addView(label("200%", 11f, Color.rgb(112, 126, 147)).apply {
                gravity = Gravity.END
            })
        })

        panel.addView(Switch(activity).apply {
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

        panel.addView(Button(activity).apply {
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
                min(dpInt(480f), width - dpInt(48f)),
                WindowManager.LayoutParams.WRAP_CONTENT
            )
        }
        dialog.show()
    }

    private fun saveSettings() {
        settingsStore.save(TouchpadSettings(sensitivityPercent, naturalScrolling))
        server.updateSettings(sensitivityPercent, naturalScrolling)
    }

    private fun label(textValue: String, size: Float, color: Int, bold: Boolean = false) =
        TextView(activity).apply {
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
