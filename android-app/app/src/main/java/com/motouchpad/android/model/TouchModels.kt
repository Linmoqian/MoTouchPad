package com.motouchpad.android.model

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

enum class FrameType(val wireValue: Byte) {
    HELLO(1),
    TOUCH(2);

    companion object {
        fun fromWireValue(value: Int): FrameType = entries.firstOrNull {
            it.wireValue.toInt() == value
        } ?: error("Unsupported frame type $value")
    }
}

data class TouchContact(
    val id: Int,
    val touching: Boolean,
    val x: Float,
    val y: Float,
    val pressure: Float,
    val major: Float,
    val minor: Float
)

data class TouchFrame(
    val type: FrameType,
    val sequence: Long,
    val timestampNanos: Long,
    val buttons: Int,
    val sensitivityPercent: Int,
    val naturalScrolling: Boolean,
    val contacts: List<TouchContact>
)

data class TouchpadSettings(
    val sensitivityPercent: Int = 100,
    val naturalScrolling: Boolean = false
)
