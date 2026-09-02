package com.motouchpad.android.protocol

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

import com.motouchpad.android.model.FrameType
import com.motouchpad.android.model.TouchContact
import com.motouchpad.android.model.TouchFrame
import java.nio.ByteBuffer
import java.nio.ByteOrder

object TouchProtocol {
    const val PORT = 47651
    const val MAGIC = 0x3150544D
    const val VERSION = 1
    const val TYPE_HELLO = 1
    const val TYPE_TOUCH = 2
    const val HEARTBEAT = 0x7F
    const val MAX_CONTACTS = 5
    const val HEADER_SIZE = 24
    const val CONTACT_SIZE = 24
}

object TouchFrameCodec {
    fun encode(frame: TouchFrame): ByteArray {
        require(frame.contacts.size <= TouchProtocol.MAX_CONTACTS) {
            "Too many contacts: ${frame.contacts.size}"
        }
        require(
            (frame.type == FrameType.HELLO && frame.contacts.isEmpty()) ||
                frame.type == FrameType.TOUCH
        ) { "Invalid frame payload" }
        val sensitivity = normalizeSensitivity(frame.sensitivityPercent)
        val buffer = ByteBuffer
            .allocate(TouchProtocol.HEADER_SIZE + frame.contacts.size * TouchProtocol.CONTACT_SIZE)
            .order(ByteOrder.LITTLE_ENDIAN)
        buffer.putInt(TouchProtocol.MAGIC)
        buffer.put(TouchProtocol.VERSION.toByte())
        buffer.put(frame.type.wireValue)
        buffer.putShort(0)
        buffer.putInt(frame.sequence.toInt())
        buffer.putLong(frame.timestampNanos)
        buffer.put(frame.contacts.size.toByte())
        buffer.put(frame.buttons.coerceIn(0, 255).toByte())
        buffer.put(sensitivity.toByte())
        buffer.put(if (frame.naturalScrolling) 1 else 0)
        frame.contacts.forEach { contact ->
            validateContact(contact)
            buffer.put(contact.id.coerceIn(0, 255).toByte())
            buffer.put(if (contact.touching) 1 else 0)
            buffer.putShort(0)
            buffer.putFloat(contact.x)
            buffer.putFloat(contact.y)
            buffer.putFloat(contact.pressure)
            buffer.putFloat(contact.major)
            buffer.putFloat(contact.minor)
        }
        return buffer.array()
    }

    fun decode(bytes: ByteArray): TouchFrame {
        require(bytes.size >= TouchProtocol.HEADER_SIZE) { "Frame is shorter than header" }
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        require(buffer.int == TouchProtocol.MAGIC) { "Invalid frame magic" }
        require(buffer.get().toInt() and 0xFF == TouchProtocol.VERSION) {
            "Unsupported protocol version"
        }
        val type = FrameType.fromWireValue(buffer.get().toInt() and 0xFF)
        require((buffer.short.toInt() and 0xFFFF) == 0) { "Reserved header flags must be zero" }
        val sequence = buffer.int.toLong() and 0xFFFF_FFFFL
        val timestamp = buffer.long
        val count = buffer.get().toInt() and 0xFF
        val buttons = buffer.get().toInt() and 0xFF
        val sensitivity = normalizeSensitivity(buffer.get().toInt() and 0xFF)
        val settingsFlags = buffer.get().toInt() and 0xFF
        require(settingsFlags and 0xFE == 0) { "Unknown settings flags" }
        val naturalScrolling = settingsFlags and 0x01 != 0
        require(count <= TouchProtocol.MAX_CONTACTS) { "Invalid contact count $count" }
        require(bytes.size == TouchProtocol.HEADER_SIZE + count * TouchProtocol.CONTACT_SIZE) {
            "Invalid frame length ${bytes.size}"
        }
        require(type != FrameType.HELLO || count == 0) { "Hello must be empty" }

        val contacts = buildList(count) {
            repeat(count) {
                val id = buffer.get().toInt() and 0xFF
                val state = buffer.get().toInt() and 0xFF
                require(state == 0 || state == 1) { "Invalid contact state $state" }
                val reserved = buffer.short.toInt() and 0xFFFF
                require(reserved == 0) { "Reserved contact bytes must be zero" }
                val contact = TouchContact(
                    id = id,
                    touching = state == 1,
                    x = buffer.float,
                    y = buffer.float,
                    pressure = buffer.float,
                    major = buffer.float,
                    minor = buffer.float
                )
                validateContact(contact)
                add(contact)
            }
        }
        return TouchFrame(
            type = type,
            sequence = sequence,
            timestampNanos = timestamp,
            buttons = buttons,
            sensitivityPercent = sensitivity,
            naturalScrolling = naturalScrolling,
            contacts = contacts
        )
    }

    private fun normalizeSensitivity(raw: Int): Int {
        require(raw == 0 || raw in 50..200) { "Invalid sensitivity $raw" }
        return if (raw == 0) 100 else raw
    }

    private fun validateContact(contact: TouchContact) {
        require(contact.id in 0..255) { "Invalid contact id" }
        listOf(contact.x, contact.y, contact.pressure, contact.major, contact.minor)
            .forEach { value ->
                require(value.isFinite() && value in 0f..1f) { "Invalid contact value $value" }
            }
    }
}
